import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/cola_practica_archivo.dart';
import 'package:spelling_bee/core/practica_service.dart';
import 'package:spelling_bee/core/registro_practica_pendiente.dart';
import 'package:spelling_bee/core/sincronizador_practica.dart';

// T-062 (RF-33): igual que niveles_controller_test.dart (T-061), plain
// test(), NO testWidgets() — ColaPracticaArchivo hace dart:io real, y la
// zona de reloj falso de testWidgets() puede dejar ese tipo de I/O sin
// resolver nunca. El comportamiento en pantalla (qué mensaje ve el alumno,
// que se llame a encolar() cuando guardarPractica() falla por SIN_CONEXION)
// se prueba en practica_palabra_screen_test.dart con un ColaPractica falso
// en memoria; aquí se prueba el MOTOR: qué manda, qué borra, qué dispara
// cuándo, y que dos intentos solapados nunca dupliquen el envío.
class _BackendSyncSimulado {
  final List<Map<String, dynamic>> lotesRecibidos = [];

  http.Response responder(http.BaseRequest request) {
    if (request is http.Request &&
        request.method == 'POST' &&
        request.url.path == '/practica/sync') {
      lotesRecibidos.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    throw StateError(
      'Ruta no simulada en la prueba: ${request.method} ${request.url.path}',
    );
  }
}

class _ClienteHttpDePrueba extends http.BaseClient {
  _ClienteHttpDePrueba(this._backend);

  final _BackendSyncSimulado _backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final respuesta = _backend.responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(respuesta.body)),
      respuesta.statusCode,
      headers: respuesta.headers,
    );
  }
}

/// Como /practica/sync (T-063) todavía no existe de verdad, así es como
/// falla en la práctica: el backend responde 404 con el mismo formato de
/// error que cualquier ruta no encontrada (ver backend/src/common/filters/
/// http-exception.filter.ts) — ApiClient lo envuelve en un ApiException
/// normal, no una excepción de transporte.
class _ClienteRutaNoExiste extends http.BaseClient {
  int vecesLlamado = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    vecesLlamado++;
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'error': {'code': 'VALIDACION', 'message': 'Cannot POST /practica/sync'},
          }),
        ),
      ),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// Cliente cuyo send() se queda colgado hasta que la prueba libera la
/// respuesta a mano — necesario para probar que una segunda llamada a
/// intentarSincronizar() lanzada MIENTRAS la primera sigue en vuelo no
/// manda un segundo POST /practica/sync en paralelo.
class _ClienteConControlManual extends http.BaseClient {
  int vecesLlamado = 0;
  final List<Completer<http.StreamedResponse>> _pendientes = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    vecesLlamado++;
    final completador = Completer<http.StreamedResponse>();
    _pendientes.add(completador);
    return completador.future;
  }

  void resolverSiguiente() {
    final completador = _pendientes.removeAt(0);
    completador.complete(
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200),
    );
  }
}

void main() {
  late Directory directorioTemporal;

  setUp(() async {
    directorioTemporal = await Directory.systemTemp.createTemp(
      'sincronizador_practica_test_',
    );
  });

  tearDown(() async {
    if (await directorioTemporal.exists()) {
      await directorioTemporal.delete(recursive: true);
    }
  });

  ColaPracticaArchivo crearCola() =>
      ColaPracticaArchivo(directorio: () async => directorioTemporal);

  RegistroPracticaPendiente registroDePrueba({
    String id = 'id-1',
    int idPalabra = 10,
  }) {
    return RegistroPracticaPendiente(
      id: id,
      idPalabra: idPalabra,
      tiempoSegundos: 42,
      oracionAlumno: 'This is my business.',
      deletreoCorrecto: true,
      fechaLocal: '2026-09-15',
    );
  }

  test(
    'intentarSincronizar() con la cola vacía no manda ninguna petición',
    () async {
      final backend = _BackendSyncSimulado();
      final sincronizador = SincronizadorPractica(
        cola: crearCola(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpDePrueba(backend)),
        ),
      );

      await sincronizador.intentarSincronizar();

      expect(backend.lotesRecibidos, isEmpty);
      expect(sincronizador.pendientes, 0);
    },
  );

  test(
    'RF-33: intentarSincronizar() exitoso manda el lote completo y vacía la cola',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba(id: 'id-1', idPalabra: 10));
      await cola.agregar(registroDePrueba(id: 'id-2', idPalabra: 11));

      final backend = _BackendSyncSimulado();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpDePrueba(backend)),
        ),
      );

      await sincronizador.intentarSincronizar();

      expect(backend.lotesRecibidos, hasLength(1));
      final registros =
          backend.lotesRecibidos.single['registros'] as List<dynamic>;
      expect(registros, hasLength(2));
      expect(
        (registros[0] as Map<String, dynamic>)['id_palabra'],
        10,
        reason: 'mismo shape que POST /practica, ver diseno-tecnico.md §3.6',
      );
      expect(await cola.listarPendientes(), isEmpty);
      expect(sincronizador.pendientes, 0);
    },
  );

  test(
    'RF-33: si la sincronización falla (T-063 todavía no existe), ningún registro se pierde de la cola',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba());

      final clienteQueFalla = _ClienteRutaNoExiste();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: clienteQueFalla),
        ),
      );

      await sincronizador.intentarSincronizar();

      expect(clienteQueFalla.vecesLlamado, 1);
      expect(
        await cola.listarPendientes(),
        hasLength(1),
        reason: 'RF-33: "sin descartar ningún registro... mientras no se confirme su envío exitoso"',
      );
      expect(sincronizador.pendientes, 1);
    },
  );

  test(
    'encolar() persiste el registro de inmediato, incluso si la sincronización oportunista falla',
    () async {
      final cola = crearCola();
      final clienteQueFalla = _ClienteRutaNoExiste();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: clienteQueFalla),
        ),
      );

      await sincronizador.encolar(registroDePrueba());

      final pendientes = await cola.listarPendientes();
      expect(
        pendientes,
        hasLength(1),
        reason:
            'RF-33: el registro debe quedar guardado en disco de inmediato, sin depender de que el intento oportunista de red tenga éxito',
      );

      // encolar() dispara intentarSincronizar() sin esperarlo (unawaited) —
      // se le da tiempo real a terminar (falla igual, pero toca disco al
      // hacerlo) antes de que termine la prueba: si sigue en vuelo cuando
      // tearDown() borra el directorio temporal, Windows rechaza el borrado
      // por archivo en uso. No es un fallo de la clase, es housekeeping de
      // esta prueba.
      await Future.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'un registro encolado MIENTRAS un lote anterior sigue en vuelo no se pierde ni se borra por error',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba(id: 'ya-en-vuelo'));

      final clienteControlado = _ClienteConControlManual();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: clienteControlado),
        ),
      );

      final intentoEnVuelo = sincronizador.intentarSincronizar();
      // Deja que llegue al await de red — intentarSincronizar() lee la cola
      // de disco de verdad antes de eso, así que un solo Duration.zero (un
      // tick) no siempre alcanza.
      await Future.delayed(const Duration(milliseconds: 30));

      // Mientras el primer lote sigue esperando respuesta, se encola un
      // registro NUEVO — no debía haber viajado en el lote que ya está en
      // vuelo, así que tampoco debe borrarse cuando ese lote se confirme.
      await cola.agregar(registroDePrueba(id: 'nuevo-durante-el-envio'));

      clienteControlado.resolverSiguiente();
      await intentoEnVuelo;

      final pendientes = await cola.listarPendientes();
      expect(
        pendientes.map((r) => r.id).toList(),
        ['nuevo-durante-el-envio'],
        reason:
            'solo se confirmó el envío de "ya-en-vuelo"; el registro agregado después debe seguir pendiente',
      );
    },
  );

  test(
    'llamadas solapadas a intentarSincronizar() nunca mandan el mismo lote dos veces en paralelo',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba());

      final clienteControlado = _ClienteConControlManual();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: clienteControlado),
        ),
      );

      final primerIntento = sincronizador.intentarSincronizar();
      // Deja que el primero llegue de verdad al await de red (pasa antes
      // por una lectura de disco real vía el mutex de ColaPracticaArchivo,
      // así que un solo Duration.zero no siempre alcanza).
      await Future.delayed(const Duration(milliseconds: 30));
      final segundoIntento = sincronizador.intentarSincronizar();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(
        clienteControlado.vecesLlamado,
        1,
        reason: 'el segundo intentarSincronizar() debió no hacer nada mientras el primero seguía en vuelo',
      );

      clienteControlado.resolverSiguiente();
      await Future.wait([primerIntento, segundoIntento]);

      expect(await cola.listarPendientes(), isEmpty);
    },
  );

  test(
    'RF-33: iniciar() intenta de inmediato y luego reintenta automáticamente cada intervalo configurado, sin intervención del alumno',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba());

      // El endpoint sigue fallando en cada intento (simula T-063 todavía
      // sin existir) — lo que se prueba aquí es que el temporizador SIGUE
      // reintentando solo, no que eventualmente tenga éxito.
      final clienteQueFalla = _ClienteRutaNoExiste();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: clienteQueFalla),
        ),
        intervaloReintento: const Duration(milliseconds: 50),
      );
      addTearDown(sincronizador.dispose);

      await sincronizador.iniciar();
      // iniciar() dispara este primer intento sin esperarlo (unawaited) —
      // y ese intento lee la cola de disco de verdad antes de llegar a la
      // red, así que hace falta darle un momento real para progresar.
      await Future.delayed(const Duration(milliseconds: 30));
      expect(
        clienteQueFalla.vecesLlamado,
        1,
        reason: 'iniciar() debe intentar de inmediato, sin esperar el primer tick',
      );

      // Intervalo de 50ms: una ventana de 300ms da margen de sobra incluso
      // si algún intento individual tarda más de lo esperado en disco.
      await Future.delayed(const Duration(milliseconds: 300));

      expect(
        clienteQueFalla.vecesLlamado,
        greaterThanOrEqualTo(3),
        reason: 'debió reintentar varias veces solo, sin que "el alumno abriera la app de nuevo"',
      );
      expect(
        await cola.listarPendientes(),
        hasLength(1),
        reason: 'sigue sin confirmarse ningún envío exitoso, así que el registro no debe perderse',
      );
    },
  );
}

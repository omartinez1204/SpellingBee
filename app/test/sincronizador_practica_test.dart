import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/cola_practica_archivo.dart';
import 'package:spelling_bee/core/monitor_conectividad.dart';
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

/// RF-38 (T-065): falla de transporte real (sin llegar a ninguna respuesta) —
/// lo que ve la app con el servidor apagado (conexión rechazada).
class _ClienteQueLanzaExcepcionDeRed extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw Exception('conexión rechazada (simulada)');
  }
}

/// T-064 (RF-34): falso 100% en memoria — mismo motivo que los http.BaseClient
/// falsos de arriba: sin esto, SincronizadorPractica.iniciar() construiría un
/// MonitorConectividadReal de verdad, que toca un canal de plataforma
/// (connectivity_plus) inexistente bajo plain test() (sin el binding de
/// testWidgets()).
class _MonitorConectividadFalso implements MonitorConectividad {
  _MonitorConectividadFalso({EstadoConexion inicial = EstadoConexion.enLinea})
    : _actual = inicial;

  EstadoConexion _actual;
  final _controlador = StreamController<EstadoConexion>.broadcast();

  @override
  Future<EstadoConexion> obtenerActual() async => _actual;

  @override
  Stream<EstadoConexion> get cambios => _controlador.stream;

  void simularCambio(EstadoConexion estado) {
    _actual = estado;
    _controlador.add(estado);
  }

  void cerrar() => _controlador.close();
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
        // T-064: inyectado para no tocar connectivity_plus real (ver
        // _MonitorConectividadFalso) — esta prueba es sobre el temporizador
        // de reintento, no sobre conectividad.
        monitorConectividad: _MonitorConectividadFalso(),
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

  test(
    'RF-34: antes de iniciar() el estado de conexión es optimista (en línea); iniciar() lo corrige con el valor real de MonitorConectividad',
    () async {
      final monitorFalso = _MonitorConectividadFalso(
        inicial: EstadoConexion.sinConexion,
      );
      addTearDown(monitorFalso.cerrar);
      final sincronizador = SincronizadorPractica(
        cola: crearCola(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteRutaNoExiste()),
        ),
        monitorConectividad: monitorFalso,
      );
      addTearDown(sincronizador.dispose);

      expect(sincronizador.estadoConexion, EstadoConexion.enLinea);

      await sincronizador.iniciar();

      expect(sincronizador.estadoConexion, EstadoConexion.sinConexion);

      // iniciar() también dispara un intentarSincronizar() inicial sin
      // esperarlo (unawaited, incluso con la cola vacía sigue tocando disco
      // una vez más en su bloque finally) — se le da tiempo real a terminar
      // antes de que el addTearDown(sincronizador.dispose) de arriba se
      // ejecute (mismo motivo que en encolar(), más arriba en este archivo).
      await Future.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'RF-34: un cambio de conectividad reportado por MonitorConectividad después de iniciar() actualiza estadoConexion de inmediato',
    () async {
      final monitorFalso = _MonitorConectividadFalso();
      addTearDown(monitorFalso.cerrar);
      final sincronizador = SincronizadorPractica(
        cola: crearCola(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteRutaNoExiste()),
        ),
        monitorConectividad: monitorFalso,
      );
      addTearDown(sincronizador.dispose);
      await sincronizador.iniciar();
      expect(sincronizador.estadoConexion, EstadoConexion.enLinea);

      monitorFalso.simularCambio(EstadoConexion.sinConexion);
      await Future.delayed(Duration.zero);

      expect(sincronizador.estadoConexion, EstadoConexion.sinConexion);

      // Ver el comentario equivalente en la prueba anterior: deja asentar el
      // intentarSincronizar() inicial de iniciar() antes de dispose().
      await Future.delayed(const Duration(milliseconds: 50));
    },
  );

  test(
    'RF-33/RF-34: al reconectar (según MonitorConectividad) se sincroniza de inmediato, sin esperar el temporizador',
    () async {
      final cola = crearCola();
      final backend = _BackendSyncSimulado();
      final monitorFalso = _MonitorConectividadFalso(
        inicial: EstadoConexion.sinConexion,
      );
      addTearDown(monitorFalso.cerrar);
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpDePrueba(backend)),
        ),
        monitorConectividad: monitorFalso,
        // Deliberadamente largo: si el lote de todas formas llega, es por la
        // reconexión simulada abajo, no por este temporizador.
        intervaloReintento: const Duration(minutes: 5),
      );
      addTearDown(sincronizador.dispose);

      // Cola vacía en este momento: el intento inmediato que dispara
      // iniciar() no manda nada — así el único candidato a mandar el lote
      // de abajo es la reconexión simulada, no el arranque.
      await sincronizador.iniciar();
      await cola.agregar(registroDePrueba());

      monitorFalso.simularCambio(EstadoConexion.enLinea);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(backend.lotesRecibidos, hasLength(1));
      expect(await cola.listarPendientes(), isEmpty);
      expect(sincronizador.estadoConexion, EstadoConexion.enLinea);
    },
  );

  test(
    'RF-34: sincronizacionesExitosas emite la cantidad de registros justo después de un lote exitoso',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba(id: 'id-1'));
      await cola.agregar(registroDePrueba(id: 'id-2', idPalabra: 11));

      final backend = _BackendSyncSimulado();
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpDePrueba(backend)),
        ),
      );
      addTearDown(sincronizador.dispose);

      final cantidades = <int>[];
      final suscripcion = sincronizador.sincronizacionesExitosas.listen(
        cantidades.add,
      );
      addTearDown(suscripcion.cancel);

      await sincronizador.intentarSincronizar();

      expect(cantidades, [2]);
    },
  );

  test(
    'RF-34: sincronizacionesExitosas no emite nada cuando no hay nada pendiente que sincronizar',
    () async {
      final backend = _BackendSyncSimulado();
      final sincronizador = SincronizadorPractica(
        cola: crearCola(),
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpDePrueba(backend)),
        ),
      );
      addTearDown(sincronizador.dispose);

      final cantidades = <int>[];
      final suscripcion = sincronizador.sincronizacionesExitosas.listen(
        cantidades.add,
      );
      addTearDown(suscripcion.cancel);

      await sincronizador.intentarSincronizar();

      expect(cantidades, isEmpty);
      expect(backend.lotesRecibidos, isEmpty);
    },
  );

  test(
    'RF-34: sincronizacionesExitosas no emite nada cuando la sincronización falla',
    () async {
      final cola = crearCola();
      await cola.agregar(registroDePrueba());

      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(httpClient: _ClienteRutaNoExiste()),
        ),
      );
      addTearDown(sincronizador.dispose);

      final cantidades = <int>[];
      final suscripcion = sincronizador.sincronizacionesExitosas.listen(
        cantidades.add,
      );
      addTearDown(suscripcion.cancel);

      await sincronizador.intentarSincronizar();

      expect(cantidades, isEmpty);
    },
  );

  // RF-38 (T-065): reintento manual — el botón "Reintentar" que aparece
  // cuando guardar una práctica no llegó al servidor.
  group('sincronizarAhora() (RF-38, T-065)', () {
    SincronizadorPractica crearSincronizador(
      ColaPracticaArchivo cola,
      http.Client cliente,
    ) {
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: PracticaService(
          apiClient: ApiClient(
            httpClient: cliente,
            monitorConectividad: _MonitorConectividadFalso(),
          ),
        ),
        monitorConectividad: _MonitorConectividadFalso(),
      );
      addTearDown(sincronizador.dispose);
      return sincronizador;
    }

    test('con la cola vacía regresa null y no manda ninguna petición', () async {
      final backend = _BackendSyncSimulado();
      final sincronizador = crearSincronizador(
        crearCola(),
        _ClienteHttpDePrueba(backend),
      );

      final error = await sincronizador.sincronizarAhora();

      expect(error, isNull);
      expect(backend.lotesRecibidos, isEmpty);
    });

    test(
      'si el envío tiene éxito, regresa null, vacía la cola y emite la confirmación de RF-34',
      () async {
        final cola = crearCola();
        await cola.agregar(registroDePrueba(id: 'id-1'));
        final backend = _BackendSyncSimulado();
        final sincronizador = crearSincronizador(
          cola,
          _ClienteHttpDePrueba(backend),
        );
        final cantidades = <int>[];
        final suscripcion = sincronizador.sincronizacionesExitosas.listen(
          cantidades.add,
        );
        addTearDown(suscripcion.cancel);

        final error = await sincronizador.sincronizarAhora();

        expect(error, isNull);
        expect(backend.lotesRecibidos, hasLength(1));
        expect(await cola.listarPendientes(), isEmpty);
        expect(sincronizador.pendientes, 0);
        expect(cantidades, [1]);
      },
    );

    test(
      'si el servidor sigue sin responder, REGRESA el error (para volver a avisar) y el registro sigue en la cola',
      () async {
        final cola = crearCola();
        await cola.agregar(registroDePrueba(id: 'id-1'));
        final sincronizador = crearSincronizador(
          cola,
          _ClienteQueLanzaExcepcionDeRed(),
        );
        final cantidades = <int>[];
        final suscripcion = sincronizador.sincronizacionesExitosas.listen(
          cantidades.add,
        );
        addTearDown(suscripcion.cancel);

        final error = await sincronizador.sincronizarAhora();

        expect(error, isNotNull);
        expect(error!.code, 'SIN_CONEXION');
        expect(error.esBackendNoDisponible, isTrue);
        expect(
          await cola.listarPendientes(),
          hasLength(1),
          reason: 'RF-33: nunca se descarta un registro sin confirmar su envío',
        );
        expect(sincronizador.pendientes, 1);
        expect(cantidades, isEmpty);
      },
    );

    test(
      'ESPERA a que termine un envío ya en vuelo en vez de descartarse — y no duplica el POST',
      () async {
        final cola = crearCola();
        await cola.agregar(registroDePrueba(id: 'id-1'));
        final cliente = _ClienteConControlManual();
        final sincronizador = crearSincronizador(cola, cliente);

        // El envío que lanzó, por ejemplo, encolar() un instante antes.
        final enVuelo = sincronizador.intentarSincronizar();
        await Future.delayed(const Duration(milliseconds: 30));
        expect(cliente.vecesLlamado, 1);

        var termino = false;
        final manual = sincronizador.sincronizarAhora().then((error) {
          termino = true;
          return error;
        });
        await Future.delayed(const Duration(milliseconds: 30));
        expect(
          termino,
          isFalse,
          reason: 'debe esperar al envío en vuelo, no regresar un resultado a ciegas',
        );
        expect(cliente.vecesLlamado, 1, reason: 'sin un segundo POST en paralelo');

        cliente.resolverSiguiente();
        final error = await manual;
        await enVuelo;

        expect(error, isNull);
        expect(
          cliente.vecesLlamado,
          1,
          reason: 'el envío en vuelo ya vació la cola — no queda nada que mandar',
        );
        expect(await cola.listarPendientes(), isEmpty);
      },
    );
  });
}

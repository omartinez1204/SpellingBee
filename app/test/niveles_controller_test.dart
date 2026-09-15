import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/almacen_paquetes_archivo.dart';
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/cache_audio_archivo.dart';
import 'package:spelling_bee/core/niveles_controller.dart';
import 'package:spelling_bee/core/niveles_service.dart';

// T-061 (RF-31/RF-32): pruebas de NivelesController con almacenamiento REAL
// en disco (AlmacenPaquetesArchivo + CacheAudioArchivo, ambas sobre un
// directorio temporal propio de cada prueba) — a propósito plain test(), NO
// testWidgets(): estas dos clases hacen dart:io real (archivos), y la zona
// de reloj falso de testWidgets()/pumpAndSettle() puede dejar ese tipo de
// I/O sin resolver nunca (fue justo el problema encontrado al escribir
// niveles_screen_test.dart la primera vez). Aquí, sin binding de widgets de
// por medio, un `await` normal es suficiente — igual que
// cache_audio_archivo_test.dart (T-033) y almacen_paquetes_archivo_test.dart
// ya prueban cada pieza suelta con el mismo criterio.
//
// La UI (qué se ve en pantalla) se prueba aparte en niveles_screen_test.dart
// con dobles en memoria; aquí se prueba la ORQUESTACIÓN real: que
// descargar() de verdad deja el audio en el mismo disco/misma clave que
// usaría el reproductor, y que ese contenido sigue disponible en una
// sesión posterior sin ninguna conexión.
class _BackendSimulado {
  _BackendSimulado({this.palabrasFacil = const []});

  final List<Map<String, dynamic>> palabrasFacil;

  static const nivelFacil = {'id': 2, 'nombre': 'Fácil', 'orden': 1};
  static const nivelIntermedio = {'id': 3, 'nombre': 'Intermedio', 'orden': 2};

  http.Response responder(http.BaseRequest request) {
    final ruta = request.url.path;
    if (request.method == 'GET' && ruta == '/niveles') {
      return _json(200, [nivelFacil, nivelIntermedio]);
    }
    if (request.method == 'GET' && ruta == '/niveles/2/descarga') {
      return _json(200, {'nivel': nivelFacil, 'palabras': palabrasFacil});
    }
    throw StateError('Ruta no simulada en la prueba: ${request.method} $ruta');
  }

  http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

class _ClienteHttpDePrueba extends http.BaseClient {
  _ClienteHttpDePrueba(this._backend);

  final _BackendSimulado _backend;

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

/// Simula "modo avión": CUALQUIER petición falla como lo haría http.Client
/// real sin conectividad (una excepción de socket, no un 4xx/5xx).
class _ClienteSinConexion extends http.BaseClient {
  int vecesLlamado = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    vecesLlamado++;
    throw const SocketException('sin conexión (prueba)');
  }
}

/// http.Client real (no el simulador de JSON de arriba) que siempre
/// responde bytes fijos — usado solo para la descarga de audio real de
/// CacheAudioArchivo (T-033).
class _ClienteFalsoDeAudio extends http.BaseClient {
  _ClienteFalsoDeAudio(this._bytes);

  final List<int> _bytes;
  int vecesLlamado = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    vecesLlamado++;
    return http.StreamedResponse(Stream.value(_bytes), 200);
  }
}

void main() {
  late Directory directorioTemporal;

  setUp(() async {
    directorioTemporal = await Directory.systemTemp.createTemp(
      'niveles_controller_test_',
    );
  });

  tearDown(() async {
    if (await directorioTemporal.exists()) {
      await directorioTemporal.delete(recursive: true);
    }
  });

  NivelesController crearControlador(http.Client cliente) => NivelesController(
    token: 'token-de-prueba',
    nivelesService: NivelesService(apiClient: ApiClient(httpClient: cliente)),
    almacen: AlmacenPaquetesArchivo(
      directorio: () async => directorioTemporal,
    ),
    cacheAudio: CacheAudioArchivo(
      httpClient: cliente,
      directorio: () async => directorioTemporal,
    ),
  );

  test('cargarInicial() lista los niveles reales, ninguno descargado', () async {
    final controller = crearControlador(
      _ClienteHttpDePrueba(_BackendSimulado()),
    );

    await controller.cargarInicial();

    expect(controller.niveles.map((n) => n.nombre), ['Fácil', 'Intermedio']);
    expect(controller.estaDescargado(2), isFalse);
    expect(controller.estaDescargado(3), isFalse);
  });

  test(
    'descargar() guarda el paquete Y precachea el audio real en disco, bajo la misma clave que usaría el reproductor',
    () async {
      final backend = _BackendSimulado(
        palabrasFacil: [
          {
            'id': 10,
            'texto': 'business',
            'significado_es': 'negocio',
            'oracion_ejemplo': 'This is my business.',
            'url_audio': '/assets/audios/10.mp3',
          },
        ],
      );
      final clienteJson = _ClienteHttpDePrueba(backend);
      final bytesAudio = utf8.encode('contenido-de-audio-de-prueba');
      final clienteAudio = _ClienteFalsoDeAudio(bytesAudio);

      final controller = NivelesController(
        token: 'token-de-prueba',
        nivelesService: NivelesService(
          apiClient: ApiClient(httpClient: clienteJson),
        ),
        almacen: AlmacenPaquetesArchivo(
          directorio: () async => directorioTemporal,
        ),
        cacheAudio: CacheAudioArchivo(
          httpClient: clienteAudio,
          directorio: () async => directorioTemporal,
        ),
      );

      await controller.cargarInicial();
      await controller.descargar(2);

      expect(controller.estaDescargado(2), isTrue);
      expect(controller.errorDescarga(2), isNull);
      expect(controller.paqueteLocal(2)!.palabras.single.texto, 'business');

      // El archivo de audio existe físicamente en el mismo directorio y con
      // el mismo nombre ("10.mp3") que ReproductorAudioJustAudio → CacheAudio
      // buscarían para esta misma url — no un formato/ubicación paralela
      // inventada solo para la descarga.
      final archivoAudio = File(
        '${directorioTemporal.path}/audios_cache/10.mp3',
      );
      expect(await archivoAudio.exists(), isTrue);
      expect(await archivoAudio.readAsBytes(), bytesAudio);
    },
  );

  test(
    'si un audio falla a media descarga, el nivel NO queda marcado como descargado (todo o nada)',
    () async {
      final backend = _BackendSimulado(
        palabrasFacil: [
          {
            'id': 10,
            'texto': 'business',
            'significado_es': 'negocio',
            'oracion_ejemplo': 'x',
            'url_audio': '/assets/audios/10.mp3',
          },
        ],
      );
      final clienteAudioQueFalla = _ClienteFalsoDeAudioConError();

      final controller = NivelesController(
        token: 'token-de-prueba',
        nivelesService: NivelesService(
          apiClient: ApiClient(httpClient: _ClienteHttpDePrueba(backend)),
        ),
        almacen: AlmacenPaquetesArchivo(
          directorio: () async => directorioTemporal,
        ),
        cacheAudio: CacheAudioArchivo(
          httpClient: clienteAudioQueFalla,
          directorio: () async => directorioTemporal,
        ),
      );

      await controller.cargarInicial();
      await controller.descargar(2);

      expect(controller.estaDescargado(2), isFalse);
      expect(controller.errorDescarga(2), isNotNull);
    },
  );

  test(
    'RF-32: un nivel descargado en una sesión "en línea" sigue disponible para LISTAR y PRACTICAR (con audio) en una sesión posterior totalmente sin conexión',
    () async {
      // --- Sesión 1: "en línea" — se descarga el nivel de verdad. ---
      final backendEnLinea = _BackendSimulado(
        palabrasFacil: [
          {
            'id': 10,
            'texto': 'offline-word',
            'significado_es': 'palabra sin conexión',
            'oracion_ejemplo': 'This works offline.',
            'url_audio': '/assets/audios/10.mp3',
          },
        ],
      );
      final bytesAudioReal = utf8.encode('contenido-de-audio-real');
      final clienteAudioEnLinea = _ClienteFalsoDeAudio(bytesAudioReal);

      final sesion1 = NivelesController(
        token: 'token-de-prueba',
        nivelesService: NivelesService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba(backendEnLinea),
          ),
        ),
        almacen: AlmacenPaquetesArchivo(
          directorio: () async => directorioTemporal,
        ),
        cacheAudio: CacheAudioArchivo(
          httpClient: clienteAudioEnLinea,
          directorio: () async => directorioTemporal,
        ),
      );
      await sesion1.cargarInicial();
      await sesion1.descargar(2);
      expect(sesion1.estaDescargado(2), isTrue);
      expect(clienteAudioEnLinea.vecesLlamado, 1);

      // --- "Se cierra la app" y "se reabre en modo avión": una sesión
      // nueva, con clientes HTTP que fallan para TODO (ni siquiera llega a
      // intentar resolver la petición), apuntando al MISMO directorio en
      // disco — lo único que de verdad sobrevive un reinicio real. ---
      final clienteSinConexion = _ClienteSinConexion();
      final sesion2 = NivelesController(
        token: 'token-de-prueba',
        nivelesService: NivelesService(
          apiClient: ApiClient(httpClient: clienteSinConexion),
        ),
        almacen: AlmacenPaquetesArchivo(
          directorio: () async => directorioTemporal,
        ),
        cacheAudio: CacheAudioArchivo(
          httpClient: clienteSinConexion,
          directorio: () async => directorioTemporal,
        ),
      );

      await sesion2.cargarInicial();

      // GET /niveles SÍ se intentó (y falló) — es justo lo que dispara el
      // respaldo a lo ya descargado localmente; una sola vez, no en bucle.
      expect(clienteSinConexion.vecesLlamado, 1);

      // RF-32, "ver palabra": el nivel sigue listado y descargado aunque
      // GET /niveles haya fallado por completo (sin red desde el arranque).
      expect(sesion2.niveles.map((n) => n.id), contains(2));
      expect(sesion2.estaDescargado(2), isTrue);
      final palabra = sesion2.paqueteLocal(2)!.palabras.single;
      expect(palabra.texto, 'offline-word');
      expect(palabra.significadoEs, 'palabra sin conexión');
      expect(palabra.oracionEjemplo, 'This works offline.');

      // RF-32, "reproducir audio": el MISMO CacheAudio que usaría el
      // reproductor real (ReproductorAudioJustAudio) encuentra el archivo
      // ya en disco y regresa sin tocar la red. Cliente NUEVO y aparte
      // (distinto del usado arriba para listar) para que este contador
      // aísle específicamente la llamada de audio, sin mezclarla con el
      // intento —esperado— de GET /niveles.
      final clienteSoloParaAudio = _ClienteSinConexion();
      final cacheAudioSesion2 = CacheAudioArchivo(
        httpClient: clienteSoloParaAudio,
        directorio: () async => directorioTemporal,
      );
      final rutaLocal = await cacheAudioSesion2.obtenerRutaLocal(
        'http://10.0.2.2:3000${palabra.urlAudio}',
      );
      expect(await File(rutaLocal).readAsBytes(), bytesAudioReal);
      expect(
        clienteSoloParaAudio.vecesLlamado,
        0,
        reason:
            'el audio ya descargado debe servirse desde disco, sin ninguna petición de red — ni siquiera un intento fallido',
      );
    },
  );

  test(
    'un nivel ya descargado en una sesión previa se detecta como descargado de entrada, sin volver a llamar a /niveles/:id/descarga',
    () async {
      final primeraSesion = crearControlador(
        _ClienteHttpDePrueba(
          _BackendSimulado(
            palabrasFacil: [
              {
                'id': 10,
                'texto': 'preguardada',
                'significado_es': null,
                'oracion_ejemplo': null,
                'url_audio': null,
              },
            ],
          ),
        ),
      );
      await primeraSesion.cargarInicial();
      await primeraSesion.descargar(2);

      // Nueva sesión: si volviera a pedir /niveles/2/descarga por error, la
      // ruta no simulada de este backend (solo tiene GET /niveles) lanzaría
      // y la prueba fallaría de inmediato.
      final segundaSesion = crearControlador(
        _ClienteHttpDePrueba(_BackendSimulado()),
      );
      await segundaSesion.cargarInicial();

      expect(segundaSesion.estaDescargado(2), isTrue);
      expect(
        segundaSesion.paqueteLocal(2)!.palabras.single.texto,
        'preguardada',
      );
    },
  );
}

class _ClienteFalsoDeAudioConError extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode('no encontrado')), 404);
  }
}

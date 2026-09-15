import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/almacen_paquetes.dart';
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/cache_audio.dart';
import 'package:spelling_bee/core/detalle_palabra.dart';
import 'package:spelling_bee/core/nivel.dart';
import 'package:spelling_bee/core/niveles_controller.dart';
import 'package:spelling_bee/core/niveles_service.dart';
import 'package:spelling_bee/core/paquete_nivel.dart';
import 'package:spelling_bee/screens/niveles_screen.dart';
import 'package:spelling_bee/screens/practica_palabra_screen.dart';

// T-061 (RF-31/RF-32): estas pruebas cubren SOLO lo que se ve y se toca en
// pantalla, con dobles 100% en memoria (AlmacenPaquetes y CacheAudio
// falsos) — a propósito, NADA de dart:io real aquí. La orquestación real
// con almacenamiento en disco de verdad (que el audio quede cacheado bajo
// la misma clave que usaría el reproductor, y que sobreviva a una sesión
// posterior totalmente sin conexión) se prueba en
// niveles_controller_test.dart con plain test(), no testWidgets(): usar
// AlmacenPaquetesArchivo/CacheAudioArchivo reales dentro de un
// testWidgets() dejó esas pruebas colgadas indefinidamente (la zona de
// reloj falso de pumpAndSettle() nunca deja resolver ese dart:io real) —
// ver ese archivo para el detalle.
class _BackendSimulado {
  _BackendSimulado({this.palabrasFacil = const []});

  final List<Map<String, dynamic>> palabrasFacil;
  final List<String> rutasPedidas = [];

  static const nivelFacil = {'id': 2, 'nombre': 'Fácil', 'orden': 1};
  static const nivelIntermedio = {'id': 3, 'nombre': 'Intermedio', 'orden': 2};

  http.Response responder(http.BaseRequest request) {
    final ruta = request.url.path;
    rutasPedidas.add(ruta);

    if (request.method == 'GET' && ruta == '/niveles') {
      return _json(200, [nivelFacil, nivelIntermedio]);
    }
    if (request.method == 'GET' && ruta == '/niveles/2/descarga') {
      return _json(200, {'nivel': nivelFacil, 'palabras': palabrasFacil});
    }
    if (request.method == 'GET' && ruta == '/niveles/3/descarga') {
      return _json(200, {'nivel': nivelIntermedio, 'palabras': []});
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

/// AlmacenPaquetes en memoria — nada de archivos reales.
class _AlmacenDePrueba implements AlmacenPaquetes {
  final Map<int, PaqueteNivel> _paquetes = {};

  void precargar(PaqueteNivel paquete) => _paquetes[paquete.nivel.id] = paquete;

  @override
  Future<void> guardar(PaqueteNivel paquete) async {
    _paquetes[paquete.nivel.id] = paquete;
  }

  @override
  Future<PaqueteNivel?> obtener(int idNivel) async => _paquetes[idNivel];

  @override
  Future<List<PaqueteNivel>> listarTodos() async => _paquetes.values.toList();
}

/// CacheAudio en memoria — evita descargas HTTP reales de audio; la
/// persistencia real en disco ya la cubren cache_audio_archivo_test.dart
/// (T-033) y niveles_controller_test.dart (T-061).
class _CacheAudioDePrueba implements CacheAudio {
  final List<String> urlsPedidas = [];
  String? urlQueFalla;

  @override
  Future<String> obtenerRutaLocal(String url) async {
    urlsPedidas.add(url);
    if (url == urlQueFalla) {
      throw Exception('fallo de red simulado al descargar audio');
    }
    return '/ruta/falsa/${Uri.parse(url).pathSegments.last}';
  }
}

Widget _envolver(Widget child) =>
    MaterialApp(home: child, debugShowCheckedModeBanner: false);

NivelesController _controlador({
  required http.Client cliente,
  AlmacenPaquetes? almacen,
  CacheAudio? cacheAudio,
}) {
  return NivelesController(
    token: 'token-de-prueba',
    nivelesService: NivelesService(apiClient: ApiClient(httpClient: cliente)),
    almacen: almacen ?? _AlmacenDePrueba(),
    cacheAudio: cacheAudio ?? _CacheAudioDePrueba(),
  );
}

void main() {
  testWidgets(
    'RF-05/RF-31: lista los niveles con botón de descarga cuando ninguno está descargado',
    (tester) async {
      final backend = _BackendSimulado();
      final controller = _controlador(cliente: _ClienteHttpDePrueba(backend));

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fácil'), findsOneWidget);
      expect(find.text('Intermedio'), findsOneWidget);
      expect(find.text('Descargado'), findsNothing);
      expect(
        find.widgetWithText(
          FilledButton,
          'Descargar para practicar sin conexión',
        ),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'RF-31: descargar un nivel precachea el audio de cada palabra y lo marca como descargado',
    (tester) async {
      final backend = _BackendSimulado(
        palabrasFacil: [
          {
            'id': 10,
            'texto': 'business',
            'significado_es': 'negocio',
            'oracion_ejemplo': 'This is my business.',
            'url_audio': '/assets/audios/10.mp3',
          },
          {
            'id': 11,
            'texto': 'sinaudio',
            'significado_es': null,
            'oracion_ejemplo': null,
            'url_audio': null,
          },
        ],
      );
      final cacheAudio = _CacheAudioDePrueba();
      final controller = _controlador(
        cliente: _ClienteHttpDePrueba(backend),
        cacheAudio: cacheAudio,
      );

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('descargar-nivel-2')));
      await tester.pumpAndSettle();

      expect(find.text('Descargado'), findsOneWidget);
      expect(find.text('business'), findsOneWidget);
      expect(find.text('sinaudio'), findsOneWidget);
      // Solo se precachea la palabra que sí tiene audio, con la misma url
      // que arma el reproductor (baseUrl + url_audio) — nunca para la que
      // trae url_audio null.
      expect(cacheAudio.urlsPedidas, [
        'http://10.0.2.2:3000/assets/audios/10.mp3',
      ]);
    },
  );

  testWidgets(
    'RF-31: si falla la descarga de un audio, el nivel NO queda marcado como descargado y se ve el error',
    (tester) async {
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
      final cacheAudio = _CacheAudioDePrueba()
        ..urlQueFalla = 'http://10.0.2.2:3000/assets/audios/10.mp3';
      final controller = _controlador(
        cliente: _ClienteHttpDePrueba(backend),
        cacheAudio: cacheAudio,
      );

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('descargar-nivel-2')));
      await tester.pumpAndSettle();

      expect(find.text('Descargado'), findsNothing);
      expect(
        find.textContaining('No se pudo descargar el contenido'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          FilledButton,
          'Descargar para practicar sin conexión',
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'un nivel ya descargado en una sesión previa se muestra descargado de entrada, sin volver a tocar Descargar',
    (tester) async {
      final almacen = _AlmacenDePrueba()
        ..precargar(
          const PaqueteNivel(
            nivel: Nivel(id: 2, nombre: 'Fácil', orden: 1),
            palabras: [
              DetallePalabra(
                id: 10,
                texto: 'preguardada',
                significadoEs: null,
                oracionEjemplo: null,
                urlAudio: null,
              ),
            ],
          ),
        );

      final backend = _BackendSimulado();
      final controller = _controlador(
        cliente: _ClienteHttpDePrueba(backend),
        almacen: almacen,
      );

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Descargado'), findsOneWidget);
      expect(find.text('preguardada'), findsOneWidget);
    },
  );

  testWidgets(
    'un nivel descargado pero sin palabras (catálogo bloqueado, T-003) muestra un mensaje claro, no una lista vacía muda',
    (tester) async {
      final backend = _BackendSimulado();
      final controller = _controlador(cliente: _ClienteHttpDePrueba(backend));

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('descargar-nivel-2')));
      await tester.pumpAndSettle();

      expect(find.text('Descargado'), findsOneWidget);
      expect(
        find.textContaining('todavía no tiene palabras disponibles'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tocar una palabra descargada abre la práctica sin NINGUNA llamada de red para la palabra',
    (tester) async {
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
      final controller = _controlador(cliente: _ClienteHttpDePrueba(backend));

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('descargar-nivel-2')));
      await tester.pumpAndSettle();

      backend.rutasPedidas.clear();
      await tester.tap(find.text('business'));
      await tester.pumpAndSettle();

      expect(find.byType(PracticaPalabraScreen), findsOneWidget);
      // El texto de la palabra se ve de inmediato (no hay spinner de carga
      // atorado esperando una respuesta que nunca llegará offline).
      expect(find.text('business'), findsOneWidget);
      expect(find.text('negocio'), findsNothing); // pista todavía oculta.
      expect(
        backend.rutasPedidas,
        isEmpty,
        reason:
            'RF-32: la práctica de una palabra ya descargada no debe llamar a la red para obtenerla',
      );
    },
  );

  testWidgets(
    'si falla la carga inicial de niveles y no hay nada descargado, muestra el error y permite reintentar',
    (tester) async {
      var yaFallo = false;
      final cliente = _ClienteConFalloUnaVez(() => yaFallo, (v) => yaFallo = v);
      final controller = _controlador(cliente: cliente);

      await tester.pumpWidget(
        _envolver(
          NivelesScreen(token: 'token-de-prueba', controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Fácil'), findsOneWidget);
    },
  );
}

class _ClienteConFalloUnaVez extends http.BaseClient {
  _ClienteConFalloUnaVez(this._yaFallo, this._marcarFallo);

  final bool Function() _yaFallo;
  final void Function(bool) _marcarFallo;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_yaFallo()) {
      _marcarFallo(true);
      throw Exception('falla de red simulada');
    }
    final respuesta = _BackendSimulado().responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(respuesta.body)),
      respuesta.statusCode,
      headers: respuesta.headers,
    );
  }
}

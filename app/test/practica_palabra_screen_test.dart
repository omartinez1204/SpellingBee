import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/cola_practica.dart';
import 'package:spelling_bee/core/grabador_audio.dart';
import 'package:spelling_bee/core/monitor_conectividad.dart';
import 'package:spelling_bee/core/palabras_service.dart';
import 'package:spelling_bee/core/practica_service.dart';
import 'package:spelling_bee/core/registro_practica_pendiente.dart';
import 'package:spelling_bee/core/reproductor_audio.dart';
import 'package:spelling_bee/core/sincronizador_practica.dart';
import 'package:spelling_bee/screens/practica_palabra_screen.dart';

// Sin librería de mocking: un http.Client falso que regresa una respuesta
// fija, igual de simple que el _AlmacenDePruebaEnMemoria de
// auth_controller_test.dart pero para el cliente HTTP en vez del storage.
//
// T-045: además GRABA cada petición enviada (método + cuerpo decodificado),
// para que las pruebas de guardarPractica() puedan verificar qué mandó
// realmente la pantalla a POST /practica sin necesitar un backend de verdad.
class _ClienteHttpDePrueba extends http.BaseClient {
  _ClienteHttpDePrueba(this._respuesta, {this.statusCode = 200});

  final Map<String, dynamic> _respuesta;
  final int statusCode;
  final List<http.Request> peticiones = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) peticiones.add(request);
    final cuerpo = utf8.encode(jsonEncode(_respuesta));
    return http.StreamedResponse(
      Stream.value(cuerpo),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

// T-045: variante que distingue GET de POST — necesaria para probar "la
// comparación con el mejor tiempo funciona bien, pero GUARDAR falla" (o
// viceversa) sin que ambas peticiones compartan el mismo resultado, algo
// que _ClienteHttpDePrueba no puede expresar al regresar siempre la misma
// respuesta sin importar qué se le pida.
class _ClienteHttpQueFallaSoloEnPost extends http.BaseClient {
  final List<http.Request> peticiones = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) peticiones.add(request);
    if (request.method == 'POST') {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
    }
    final cuerpo = utf8.encode(jsonEncode({'mejor_tiempo_segundos': null}));
    return http.StreamedResponse(
      Stream.value(cuerpo),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

// RF-38 (T-065): variante que falla con 500 SOLO la PRIMERA vez que recibe
// un POST — para probar que el botón "Reintentar" del banner de backend-no-
// disponible de verdad reenvía la MISMA petición (mismo tiempo, misma
// oración, mismo resultado de deletreo) y esta vez sí se guarda.
class _ClienteHttpQuePrimeroFallaLuegoOk extends http.BaseClient {
  final List<http.Request> peticionesPost = [];
  var _primeraVez = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'POST') {
      final cuerpo = utf8.encode(jsonEncode({'mejor_tiempo_segundos': null}));
      return http.StreamedResponse(
        Stream.value(cuerpo),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request is http.Request) peticionesPost.add(request);
    if (_primeraVez) {
      _primeraVez = false;
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'insignia_otorgada': null}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

// RF-38 (T-065): un servidor que se cae y vuelve. Mientras [caido] sea true,
// TODA petición falla con una excepción de transporte (lo que ve la app con
// el backend apagado: conexión rechazada), sin llegar a ninguna respuesta;
// al ponerlo en false responde normal. Graba las peticiones para poder
// verificar QUÉ se reintentó.
class _ClienteServidorQueSeCaeYVuelve extends http.BaseClient {
  bool caido = true;
  final List<http.Request> peticiones = [];

  Iterable<http.Request> get envios =>
      peticiones.where((p) => p.url.path == '/practica/sync');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) peticiones.add(request);
    if (caido) throw Exception('conexión rechazada (simulada)');
    if (request.method == 'GET') {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'mejor_tiempo_segundos': null}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final cuerpo = request.url.path == '/practica/sync'
        ? '{}'
        : jsonEncode({'insignia_otorgada': null});
    return http.StreamedResponse(
      Stream.value(utf8.encode(cuerpo)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _ColaEnMemoria implements ColaPractica {
  final List<RegistroPracticaPendiente> registros = [];

  @override
  Future<void> agregar(RegistroPracticaPendiente registro) async {
    registros.add(registro);
  }

  @override
  Future<List<RegistroPracticaPendiente>> listarPendientes() async =>
      List.of(registros);

  @override
  Future<void> eliminar(String id) async {
    registros.removeWhere((r) => r.id == id);
  }
}

class _MonitorFijo implements MonitorConectividad {
  _MonitorFijo(this._estado);

  final EstadoConexion _estado;

  @override
  Future<EstadoConexion> obtenerActual() async => _estado;

  @override
  Stream<EstadoConexion> get cambios => const Stream.empty();
}

// T-030: reproductor falso — sin esto, la pantalla construiría un
// ReproductorAudioJustAudio real (just_audio), y aunque construirlo no
// truena bajo `flutter test`, reproducir()/pausar()/etc. sí necesitan un
// canal de plataforma que no existe ahí. Deja registro de qué se le pidió
// para que las pruebas puedan verificarlo (url exacta reproducida, cuántas
// veces se pausó/reanudó/detuvo) y permite simular tanto un final natural
// del audio como una falla real.
class _ReproductorFalso implements ReproductorAudio {
  final _controlador = StreamController<EstadoAudio>.broadcast();
  final _controladorPosicion = StreamController<Duration>.broadcast();
  final _controladorDuracion = StreamController<Duration?>.broadcast();
  final List<String> urlsReproducidas = [];
  int vecesPausado = 0;
  int vecesReanudado = 0;
  int vecesDetenido = 0;
  int vecesRetrocedido = 0;
  int vecesAdelantado = 0;
  bool disposed = false;
  bool fallarAlReproducir = false;

  @override
  Stream<EstadoAudio> get estado => _controlador.stream;

  @override
  Future<void> reproducir(String url) async {
    if (fallarAlReproducir) {
      throw Exception('fallo simulado de red');
    }
    urlsReproducidas.add(url);
    _controlador.add(EstadoAudio.reproduciendo);
  }

  @override
  Future<void> pausar() async {
    vecesPausado++;
    _controlador.add(EstadoAudio.pausado);
  }

  @override
  Future<void> reanudar() async {
    vecesReanudado++;
    _controlador.add(EstadoAudio.reproduciendo);
  }

  @override
  Future<void> detener() async {
    vecesDetenido++;
    _controlador.add(EstadoAudio.detenido);
  }

  // El falso no simula posición/duración real (eso vive en
  // ReproductorAudioJustAudio y se prueba aparte, sin Flutter de por medio,
  // en reproductor_audio_just_audio_test.dart) — aquí solo importa que la
  // pantalla llame al método correcto sin cambiar el estado reproduciendo/
  // pausado en el que ya estaba.
  @override
  Future<void> retroceder() async {
    vecesRetrocedido++;
  }

  @override
  Future<void> adelantar() async {
    vecesAdelantado++;
  }

  // T-032: el falso deja que cada prueba mande valores de posición/duración
  // a su antojo con emitirPosicion()/emitirDuracion() — igual que
  // simularFinNatural(), no intenta simular el ticking real de just_audio
  // (eso se prueba aparte, en reproductor_audio_just_audio_test.dart).
  @override
  Stream<Duration> get posicion => _controladorPosicion.stream;

  @override
  Stream<Duration?> get duracion => _controladorDuracion.stream;

  void emitirPosicion(Duration d) => _controladorPosicion.add(d);

  void emitirDuracion(Duration? d) => _controladorDuracion.add(d);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controlador.close();
    await _controladorPosicion.close();
    await _controladorDuracion.close();
  }

  /// RF-17: simula que el audio llegó solo a su fin (sin que nadie haya
  /// tocado "detener"), tal como haría ReproductorAudioJustAudio al ver
  /// ProcessingState.completed.
  void simularFinNatural() => _controlador.add(EstadoAudio.detenido);
}

// T-048: falso para GrabadorAudio — sin micrófono/reproductor reales, deja
// que cada prueba controle el permiso y simule fallas en cualquiera de los
// 3 pasos (grabar/reproducir/limpiar) sin depender de un canal de
// plataforma real.
class _GrabadorFalso implements GrabadorAudio {
  bool permisoConcedido = true;
  Object? errorAlIniciar;
  Object? errorAlReproducir;
  bool permisoSolicitado = false;
  bool grabacionIniciada = false;
  bool reproducido = false;
  bool disposed = false;

  @override
  Future<bool> solicitarPermiso() async {
    permisoSolicitado = true;
    return permisoConcedido;
  }

  @override
  Future<void> iniciarGrabacion() async {
    if (errorAlIniciar != null) throw errorAlIniciar!;
    grabacionIniciada = true;
  }

  @override
  Future<void> detenerYReproducir() async {
    if (errorAlReproducir != null) throw errorAlReproducir!;
    reproducido = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

// T-040: reloj falso — DateTime.now() no obedece tester.pump(duration) (a
// diferencia de los Timer, que sí corren sobre el reloj virtual de las
// pruebas de widgets), así que sin este control manual no habría forma
// determinista de probar RF-20/RNF-04.
class _RelojFalso {
  DateTime _actual = DateTime(2026);

  DateTime ahora() => _actual;

  void avanzar(Duration d) => _actual = _actual.add(d);
}

Widget _envolver(Widget child) =>
    MaterialApp(home: child, debugShowCheckedModeBanner: false);

// La pantalla completa (palabra + audio + pistas + deletreo + cronómetro) no
// cabe en los 600px de alto del viewport por defecto de las pruebas —
// tocar cualquier cosa bajo el "pliegue" necesita primero desplazarla a la
// vista dentro del SingleChildScrollView que envuelve toda la columna.
Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

const _palabraConAudio = {
  'id': 1,
  'texto': 'business',
  'significado_es': 'negocio',
  'oracion_ejemplo': 'This is a business.',
  'url_audio': '/assets/audios/1.mp3',
};

void main() {
  testWidgets(
    'muestra de inmediato la palabra y el ícono de audio, sin significado ni oración visibles',
    (tester) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: _ReproductorFalso(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('business'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ver significado'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ver ejemplo'), findsOneWidget);
      expect(find.text('negocio'), findsNothing);
      expect(find.text('This is a business.'), findsNothing);
    },
  );

  testWidgets('al presionar "Ver significado" revela el significado, no antes', (
    tester,
  ) async {
    final cliente = _ClienteHttpDePrueba(_palabraConAudio);
    final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

    await tester.pumpWidget(
      _envolver(
        PracticaPalabraScreen(
          idPalabra: 1,
          token: 'token-de-prueba',
          palabrasService: servicio,
          reproductor: _ReproductorFalso(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver significado'));
    await tester.pump();

    expect(find.text('negocio'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Ver significado'), findsNothing);
    // La otra pista sigue sin revelarse.
    expect(find.text('This is a business.'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Ver ejemplo'), findsOneWidget);
  });

  testWidgets('al presionar "Ver ejemplo" revela la oración, no antes', (
    tester,
  ) async {
    final cliente = _ClienteHttpDePrueba(_palabraConAudio);
    final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

    await tester.pumpWidget(
      _envolver(
        PracticaPalabraScreen(
          idPalabra: 1,
          token: 'token-de-prueba',
          palabrasService: servicio,
          reproductor: _ReproductorFalso(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver ejemplo'));
    await tester.pump();

    expect(find.text('This is a business.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Ver ejemplo'), findsNothing);
  });

  testWidgets(
    'si significado_es es null (palabra incompleta), la pista lo dice honestamente en vez de mostrar vacío',
    (tester) async {
      final cliente = _ClienteHttpDePrueba({
        'id': 1,
        'texto': 'business',
        'significado_es': null,
        'oracion_ejemplo': null,
        'url_audio': null,
      });
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: _ReproductorFalso(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Ver significado'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ver ejemplo'));
      await tester.pump();

      expect(
        find.text('Esta palabra todavía no tiene significado capturado.'),
        findsOneWidget,
      );
      expect(
        find.text('Esta palabra todavía no tiene oración de ejemplo capturada.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('si la palabra no existe, muestra el mensaje de error real del backend', (
    tester,
  ) async {
    final cliente = _ClienteHttpDePrueba({
      'error': {
        'code': 'PALABRA_NO_ENCONTRADA',
        'message': 'No existe una palabra con ese id.',
      },
    }, statusCode: 404);
    final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

    await tester.pumpWidget(
      _envolver(
        PracticaPalabraScreen(
          idPalabra: 999999,
          token: 'token-de-prueba',
          palabrasService: servicio,
          reproductor: _ReproductorFalso(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No existe una palabra con ese id.'), findsOneWidget);
  });

  group('reproducción de audio (T-030)', () {
    testWidgets(
      'si la palabra no tiene audio, avisa en vez de intentar reproducir',
      (tester) async {
        final cliente = _ClienteHttpDePrueba({
          'id': 1,
          'texto': 'business',
          'significado_es': null,
          'oracion_ejemplo': null,
          'url_audio': null,
        });
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pump();

        expect(
          find.text('Esta palabra todavía no tiene audio disponible.'),
          findsOneWidget,
        );
        expect(reproductor.urlsReproducidas, isEmpty);
      },
    );

    testWidgets('RF-12: al tocar el ícono, reproduce el audio con la url completa', (
      tester,
    ) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
      final reproductor = _ReproductorFalso();

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: reproductor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pumpAndSettle();

      expect(reproductor.urlsReproducidas, [
        '${servicio.baseUrl}/assets/audios/1.mp3',
      ]);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsNothing);
    });

    testWidgets('RF-13: tocar mientras reproduce pausa, tocar de nuevo reanuda', (
      tester,
    ) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
      final reproductor = _ReproductorFalso();

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: reproductor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.volume_up)); // reproducir
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.pause)); // pausar
      await tester.pumpAndSettle();
      expect(reproductor.vecesPausado, 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow)); // reanudar
      await tester.pumpAndSettle();
      expect(reproductor.vecesReanudado, 1);
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets(
      'RF-14/RF-15: retroceder y adelantar solo aparecen mientras hay algo sobre lo que actuar',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Detenido: ni retroceder ni adelantar tienen sentido todavía.
        expect(find.byIcon(Icons.replay_5), findsNothing);
        expect(find.byIcon(Icons.forward_5), findsNothing);

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.replay_5), findsOneWidget);
        expect(find.byIcon(Icons.forward_5), findsOneWidget);

        // Pausado: siguen teniendo sentido (RF-14/RF-15 dicen explícitamente
        // "mientras se reproduce o está pausada").
        await tester.tap(find.byIcon(Icons.pause));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.replay_5), findsOneWidget);
        expect(find.byIcon(Icons.forward_5), findsOneWidget);

        await tester.tap(find.byIcon(Icons.stop));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.replay_5), findsNothing);
        expect(find.byIcon(Icons.forward_5), findsNothing);
      },
    );

    testWidgets(
      'RF-14: tocar retroceder llama al reproductor sin cambiar el ícono principal',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.replay_5));
        await tester.pumpAndSettle();

        expect(reproductor.vecesRetrocedido, 1);
        // Retroceder no es pausar ni detener: se sigue reproduciendo.
        expect(find.byIcon(Icons.pause), findsOneWidget);
        expect(reproductor.vecesPausado, 0);
        expect(reproductor.vecesDetenido, 0);
      },
    );

    testWidgets(
      'RF-15: tocar adelantar llama al reproductor sin cambiar el ícono principal',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.pause)); // probar también en pausado
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.forward_5));
        await tester.pumpAndSettle();

        expect(reproductor.vecesAdelantado, 1);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
        expect(reproductor.vecesReanudado, 0);
      },
    );

    testWidgets(
      'RF-16: el botón de detener solo aparece mientras hay algo que detener, y al presionarlo resetea el ícono',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.stop), findsNothing);

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.stop), findsOneWidget);

        await tester.tap(find.byIcon(Icons.stop));
        await tester.pumpAndSettle();

        expect(reproductor.vecesDetenido, 1);
        expect(find.byIcon(Icons.stop), findsNothing);
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
      },
    );

    testWidgets('RF-17: después de detener, se puede reproducir de nuevo sin límite', (
      tester,
    ) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
      final reproductor = _ReproductorFalso();

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: reproductor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var vez = 1; vez <= 3; vez++) {
        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.pause), findsOneWidget);

        await tester.tap(find.byIcon(Icons.stop));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
      }

      expect(reproductor.urlsReproducidas, hasLength(3));
      expect(reproductor.vecesDetenido, 3);
    });

    testWidgets(
      'RF-17: si el audio termina solo (sin detener), queda listo para reproducirse de nuevo',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.pause), findsOneWidget);

        reproductor.simularFinNatural();
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.volume_up), findsOneWidget);
        expect(find.byIcon(Icons.stop), findsNothing);

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        expect(reproductor.urlsReproducidas, hasLength(2));
      },
    );

    testWidgets('si falla la reproducción, avisa sin tronar y deja reintentar', (
      tester,
    ) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
      final reproductor = _ReproductorFalso()..fallarAlReproducir = true;

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: reproductor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo reproducir el audio.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // No se quedó atorado mostrando otra cosa que el ícono inicial.
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      reproductor.fallarAlReproducir = false;
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pumpAndSettle();
      expect(reproductor.urlsReproducidas, hasLength(1));
    });

    testWidgets('al salir de la pantalla, se libera el reproductor', (tester) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
      final reproductor = _ReproductorFalso();

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: reproductor,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(reproductor.disposed, isTrue);
    });

    testWidgets(
      'RF-18: la barra de progreso y el texto de tiempo solo aparecen mientras hay algo que reproducir',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsNothing);

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();

        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'RF-18: el texto muestra transcurrido/total en formato mm:ss, como el ejemplo del ERS',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();

        // Antes de conocer la duración: "--:--" en vez de una duración
        // inventada o un cero engañoso.
        expect(find.text('00:00 / --:--'), findsOneWidget);

        reproductor.emitirDuracion(const Duration(seconds: 12));
        reproductor.emitirPosicion(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        expect(find.text('00:03 / 00:12'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-18: la barra de progreso refleja la proporción transcurrido/total',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();

        reproductor.emitirDuracion(const Duration(seconds: 20));
        reproductor.emitirPosicion(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        final barra = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(barra.value, closeTo(0.25, 0.001));
      },
    );

    testWidgets(
      'RF-16/RF-18: al detener, el tiempo transcurrido regresa a 00:00',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: reproductor,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.volume_up));
        await tester.pumpAndSettle();
        reproductor.emitirDuracion(const Duration(seconds: 12));
        reproductor.emitirPosicion(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        expect(find.text('00:09 / 00:12'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.stop));
        await tester.pumpAndSettle();

        // La barra completa desaparece en "detenido" (mismo criterio que
        // retroceder/adelantar/detener) — no queda un "00:09" fantasma.
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.textContaining('00:09'), findsNothing);
      },
    );
  });

  group('cronómetro de práctica (T-040/T-041/T-042)', () {
    testWidgets(
      'RF-19: antes de iniciar, se ve fijo en 00:00 con el botón visible',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('00:00'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-19: al presionar Iniciar, el botón desaparece y el cronómetro sigue en 00:00 hasta el primer tick',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();

        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsNothing);
        expect(find.text('00:00'), findsOneWidget);

        // Limpieza: cancela el Timer.periodic antes de que termine la
        // prueba (pumpAndSettle nunca "asienta" con un periodic corriendo).
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'RF-20: el valor en pantalla avanza al menos una vez por segundo mientras corre',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();

        for (final esperado in ['00:01', '00:02', '00:03']) {
          reloj.avanzar(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text(esperado), findsOneWidget);
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'al salir de la pantalla con el cronómetro corriendo, se cancela sin error',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        reloj.avanzar(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'RF-21: "Terminé" solo aparece mientras el cronómetro está corriendo',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Antes de iniciar: ni siquiera existe.
        expect(find.widgetWithText(FilledButton, 'Terminé'), findsNothing);

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        expect(find.widgetWithText(FilledButton, 'Terminé'), findsOneWidget);

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();

        // Después de terminar: tampoco — ya no hay nada más que detener.
        expect(find.widgetWithText(FilledButton, 'Terminé'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsNothing);
      },
    );

    testWidgets(
      'RF-21: al presionar Terminé, el cronómetro se detiene y el tiempo queda fijo',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        // Sin esto, presionar "Terminé" (T-042) haría una llamada de red de
        // verdad a GET /practica/mejor-tiempo — no relevante para esta
        // prueba de RF-21, pero necesaria para no depender de la red bajo
        // `flutter test`.
        final practicaService = PracticaService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba({'mejor_tiempo_segundos': null}),
          ),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          reloj.avanzar(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('00:03'), findsOneWidget);

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        expect(find.text('00:03'), findsOneWidget);

        // El reloj sigue avanzando en el mundo real, pero sin el ticker
        // corriendo el valor mostrado ya no debe moverse — si esto fallara
        // (el Timer no se canceló), tester.pump(duration) con un periodic
        // vivo también dejaría un Timer pendiente al final de la prueba.
        reloj.avanzar(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('00:03'), findsOneWidget);
        expect(find.text('00:08'), findsNothing);
      },
    );

    testWidgets(
      'RF-22: al terminar por primera vez (mejor tiempo null), muestra el mensaje de bienvenida',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final practicaService = PracticaService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba({'mejor_tiempo_segundos': null}),
          ),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        // La consulta a PracticaService es async — pumpAndSettle espera a
        // que resuelva y a que el setState() del mensaje se pinte.
        await tester.pumpAndSettle();

        expect(find.textContaining('primer intento'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-22: si mejoró su mejor tiempo previo, lo dice mencionando la marca anterior',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final practicaService = PracticaService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba({'mejor_tiempo_segundos': 10}),
          ),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        // 3s < los 10s de mejor marca previa: debe contar como mejora.
        for (var i = 0; i < 3; i++) {
          reloj.avanzar(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Mejoraste'), findsOneWidget);
        expect(find.textContaining('00:10'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-24: si POST /practica indica que se otorgó una insignia, muestra un diálogo emergente de felicitación',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final practicaService = PracticaService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba({
              'mejor_tiempo_segundos': null,
              'insignia_otorgada': {
                'id_nivel': 1,
                'nombre_nivel': 'Fácil',
                'fecha_otorgada': '2026-01-01T00:00:00.000Z',
              },
            }),
          ),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(find.text('¡Felicidades!'), findsOneWidget);
        expect(find.textContaining('Fácil'), findsOneWidget);

        // El diálogo se puede cerrar y no deja nada pendiente.
        await tester.tap(find.widgetWithText(FilledButton, 'Aceptar'));
        await tester.pumpAndSettle();
        expect(find.text('¡Felicidades!'), findsNothing);
      },
    );

    testWidgets(
      'si POST /practica no otorga ninguna insignia (insignia_otorgada ausente), no muestra ningún diálogo',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final practicaService = PracticaService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba({'mejor_tiempo_segundos': null}),
          ),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(find.text('¡Felicidades!'), findsNothing);
      },
    );

    testWidgets(
      'si falla la consulta de mejor tiempo, avisa sin tronar y el tiempo ya fijado no se pierde',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final practicaService = PracticaService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba({}, statusCode: 500),
          ),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        reloj.avanzar(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 3));
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('No se pudo cargar tu comparación con tu mejor tiempo.'),
          findsOneWidget,
        );
        // RF-21 no depende de RF-22: el tiempo ya fijado se mantiene.
        expect(find.text('00:03'), findsOneWidget);
      },
    );
  });

  group('deletreo por bloques de letras (T-043)', () {
    testWidgets(
      'RF-25: una ficha por cada letra de la palabra, sin distractores, y "Verificar orden" arranca deshabilitado',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Ordena las letras para deletrear la palabra'),
          findsOneWidget,
        );

        // 'business' tiene 8 letras, con 's' repetida 3 veces — cada
        // POSICIÓN original debe existir exactamente una vez (disponible o
        // ya colocada), nunca duplicada ni faltante. Eso es justo lo que
        // garantiza "sin distractores": ni una ficha de más ni de menos.
        for (var i = 0; i < 'business'.length; i++) {
          final disponible = find.byKey(ValueKey('ficha-disponible-$i'));
          final colocada = find.byKey(ValueKey('ficha-colocada-$i'));
          expect(
            tester.widgetList(disponible).length +
                tester.widgetList(colocada).length,
            1,
            reason: 'la ficha de la posición $i debe existir exactamente una vez',
          );
        }

        final boton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Verificar orden'),
        );
        expect(boton.onPressed, isNull);
      },
    );

    testWidgets(
      'RF-25: al colocar las fichas en el orden correcto y verificar, indica que el deletreo es correcto',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tocar por posición ORIGINAL 0..7, en ese orden, reconstruye
        // "business" sin importar en qué orden las barajó la pantalla —
        // cada ficha lleva su posición real como key, no su letra.
        for (var i = 0; i < 'business'.length; i++) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }

        final boton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Verificar orden'),
        );
        expect(boton.onPressed, isNotNull);

        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));

        expect(find.textContaining('¡Correcto!'), findsOneWidget);
      },
    );

    testWidgets('RF-25: si el orden no coincide, lo indica sin bloquear el avance', (
      tester,
    ) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: _ReproductorFalso(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Orden deliberadamente incorrecto: intercambia las dos primeras
      // posiciones ("ubsiness..." en vez de "business...").
      for (final i in [1, 0, 2, 3, 4, 5, 6, 7]) {
        await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
      }

      await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));

      expect(find.textContaining('Todavía no es el orden correcto'), findsOneWidget);
      expect(find.textContaining('¡Correcto!'), findsNothing);

      // "Sin bloquear el avance": el resto de la pantalla (el cronómetro)
      // sigue funcionando con normalidad después de un intento fallido.
      await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
      expect(find.widgetWithText(FilledButton, 'Terminé'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'RF-25: dos fichas con la misma letra son intercambiables — no importa cuál instancia de "s" se use',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 'business' = b(0) u(1) s(2) i(3) n(4) e(5) s(6) s(7): las
        // posiciones 6 y 7 son ambas 's'. Colocar la ficha de la posición 7
        // antes que la de la posición 6 sigue deletreando "business" al
        // pie de la letra — el alumno no tiene, ni debería tener, forma de
        // distinguir una 's' de otra.
        for (final i in [0, 1, 2, 3, 4, 5, 7, 6]) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));

        expect(find.textContaining('¡Correcto!'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-25: tras un intento incorrecto, se pueden quitar las fichas colocadas y volver a intentarlo sin salir de la pantalla',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Orden deliberadamente incorrecto: 'b' y 'u' (genuinamente letras
        // distintas, a diferencia de las tres 's') intercambiadas.
        const ordenIncorrecto = [1, 0, 2, 3, 4, 5, 6, 7];
        for (final i in ordenIncorrecto) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));
        expect(find.textContaining('Todavía no es el orden correcto'), findsOneWidget);

        // Quita todas las fichas colocadas, una por una — el aviso
        // desaparece en cuanto cambia la disposición, no hace falta salir
        // de la pantalla ni recargar la palabra.
        for (final i in ordenIncorrecto) {
          await _tocar(tester, find.byKey(ValueKey('ficha-colocada-$i')));
        }
        expect(find.textContaining('Todavía no es el orden correcto'), findsNothing);

        for (var i = 0; i < 'business'.length; i++) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));

        expect(find.textContaining('¡Correcto!'), findsOneWidget);
      },
    );

    testWidgets(
      'una vez correcto, las fichas quedan fijas (ya no se pueden volver a mover)',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (var i = 0; i < 'business'.length; i++) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));
        expect(find.textContaining('¡Correcto!'), findsOneWidget);

        await _tocar(tester, find.byKey(const ValueKey('ficha-colocada-0')));

        // Si se hubiera podido quitar, el aviso de éxito habría
        // desaparecido (igual que en la prueba de corrección de arriba) y
        // la ficha 0 habría vuelto a "disponible".
        expect(find.textContaining('¡Correcto!'), findsOneWidget);
        expect(find.byKey(const ValueKey('ficha-colocada-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('ficha-disponible-0')), findsNothing);
      },
    );

    testWidgets(
      'el deletreo no depende del cronómetro: se puede completar antes de presionar Iniciar',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // El cronómetro sigue sin iniciarse durante todo este intento.
        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsOneWidget);

        for (var i = 0; i < 'business'.length; i++) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));

        expect(find.textContaining('¡Correcto!'), findsOneWidget);
        expect(find.text('00:00'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsOneWidget);
      },
    );
  });

  group('oración con la palabra practicada (T-044)', () {
    Future<void> abrirPantalla(WidgetTester tester) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: _ReproductorFalso(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('RF-26: muestra un campo de texto para escribir la oración', (
      tester,
    ) async {
      await abrirPantalla(tester);

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('RF-26: con el campo vacío no muestra ningún aviso', (tester) async {
      await abrirPantalla(tester);

      expect(find.textContaining('Todavía no incluye'), findsNothing);
    });

    testWidgets(
      'RF-26: si la oración no incluye la palabra, avisa mencionándola, sin bloquear nada',
      (tester) async {
        await abrirPantalla(tester);

        await tester.enterText(find.byType(TextField), 'This is a nice sentence.');
        await tester.pump();

        expect(find.textContaining('Todavía no incluye'), findsOneWidget);
        expect(find.textContaining('"business"'), findsOneWidget);

        // "Sin bloquear nada": el resto de la pantalla (cronómetro) sigue
        // funcionando con normalidad mientras el aviso está visible.
        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        expect(find.widgetWithText(FilledButton, 'Terminé'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'RF-26: si la oración incluye la palabra, sin importar mayúsculas/minúsculas, no avisa',
      (tester) async {
        await abrirPantalla(tester);

        await tester.enterText(find.byType(TextField), 'I work in BUSINESS.');
        await tester.pump();

        expect(find.textContaining('Todavía no incluye'), findsNothing);
      },
    );

    testWidgets(
      'RF-26: basta con que la palabra aparezca como subcadena, no como palabra completa aislada',
      (tester) async {
        await abrirPantalla(tester);

        // "Businesses" contiene "business" como subcadena literal — el
        // criterio de RF-26 es explícito en que esto NO es una validación
        // de palabra completa ni de gramática/conjugación.
        await tester.enterText(
          find.byType(TextField),
          'Businesses need good employees.',
        );
        await tester.pump();

        expect(find.textContaining('Todavía no incluye'), findsNothing);
      },
    );

    testWidgets('RF-26: el aviso desaparece en cuanto se corrige el texto', (
      tester,
    ) async {
      await abrirPantalla(tester);

      await tester.enterText(find.byType(TextField), 'This is a nice sentence.');
      await tester.pump();
      expect(find.textContaining('Todavía no incluye'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'This is a nice sentence about my business.',
      );
      await tester.pump();

      expect(find.textContaining('Todavía no incluye'), findsNothing);
    });

    testWidgets(
      'la oración no depende del cronómetro: se puede escribir antes de presionar Iniciar',
      (tester) async {
        await abrirPantalla(tester);

        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsOneWidget);

        await tester.enterText(
          find.byType(TextField),
          'This sentence mentions business.',
        );
        await tester.pump();

        expect(find.textContaining('Todavía no incluye'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Iniciar'), findsOneWidget);
      },
    );
  });

  group('guardado de la práctica (T-045)', () {
    Future<void> completarDeletreoCorrecto(WidgetTester tester) async {
      for (var i = 0; i < 'business'.length; i++) {
        await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
      }
      await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));
    }

    testWidgets(
      'RF-21/RF-27: al presionar Terminé, guarda id_palabra, tiempo, oración y resultado del deletreo tal como quedaron',
      (tester) async {
        final clientePalabras = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(
          apiClient: ApiClient(httpClient: clientePalabras),
        );
        final clientePractica = _ClienteHttpDePrueba({'mejor_tiempo_segundos': null});
        final practicaService = PracticaService(
          apiClient: ApiClient(httpClient: clientePractica),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await completarDeletreoCorrecto(tester);
        await tester.enterText(find.byType(TextField), 'I run my own business.');
        await tester.pump();

        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        for (var i = 0; i < 5; i++) {
          reloj.avanzar(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        final peticionesPost = clientePractica.peticiones.where(
          (p) => p.method == 'POST',
        );
        expect(peticionesPost, hasLength(1));
        final cuerpo = jsonDecode(peticionesPost.single.body) as Map<String, dynamic>;
        expect(cuerpo, {
          'id_palabra': 1,
          'tiempo_segundos': 5,
          'oracion_alumno': 'I run my own business.',
          'deletreo_correcto': true,
          // RF-23 (T-046): _RelojFalso arranca en DateTime(2026), es decir
          // 2026-01-01 — los pocos segundos que avanza el cronómetro en
          // esta prueba nunca cruzan a un día distinto.
          'fecha_local': '2026-01-01',
        });
        expect(
          peticionesPost.single.headers['Authorization'],
          'Bearer token-de-prueba',
        );
      },
    );

    testWidgets(
      'si nunca se tocó el deletreo ni se escribió nada, guarda deletreo_correcto=false y oracion_alumno vacía (RF-25/RF-26 no bloquean)',
      (tester) async {
        final clientePalabras = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(
          apiClient: ApiClient(httpClient: clientePalabras),
        );
        final clientePractica = _ClienteHttpDePrueba({'mejor_tiempo_segundos': null});
        final practicaService = PracticaService(
          apiClient: ApiClient(httpClient: clientePractica),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        reloj.avanzar(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        final peticionesPost = clientePractica.peticiones.where(
          (p) => p.method == 'POST',
        );
        final cuerpo = jsonDecode(peticionesPost.single.body) as Map<String, dynamic>;
        expect(cuerpo, {
          'id_palabra': 1,
          'tiempo_segundos': 2,
          'oracion_alumno': '',
          'deletreo_correcto': false,
          'fecha_local': '2026-01-01',
        });
      },
    );

    testWidgets(
      'RF-23: fecha_local refleja el día calendario AL PRESIONAR TERMINÉ, no el día en que se presionó Iniciar',
      (tester) async {
        final clientePalabras = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(
          apiClient: ApiClient(httpClient: clientePalabras),
        );
        final clientePractica = _ClienteHttpDePrueba({'mejor_tiempo_segundos': null});
        final practicaService = PracticaService(
          apiClient: ApiClient(httpClient: clientePractica),
        );
        final reloj = _RelojFalso(); // arranca en 2026-01-01 00:00:00.

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        // Cruza la medianoche mientras el cronómetro sigue corriendo: para
        // cuando se presione "Terminé", ya es 2026-01-02, no 2026-01-01.
        reloj.avanzar(const Duration(hours: 23, minutes: 59, seconds: 59));
        await tester.pump(const Duration(seconds: 1));
        reloj.avanzar(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));

        await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        final peticionesPost = clientePractica.peticiones.where(
          (p) => p.method == 'POST',
        );
        final cuerpo = jsonDecode(peticionesPost.single.body) as Map<String, dynamic>;
        expect(cuerpo['fecha_local'], '2026-01-02');
      },
    );

    testWidgets(
      'si el deletreo se verificó pero quedó incorrecto, guarda deletreo_correcto=false',
      (tester) async {
        final clientePalabras = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(
          apiClient: ApiClient(httpClient: clientePalabras),
        );
        final clientePractica = _ClienteHttpDePrueba({'mejor_tiempo_segundos': null});
        final practicaService = PracticaService(
          apiClient: ApiClient(httpClient: clientePractica),
        );

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Orden deliberadamente incorrecto (mismo patrón que T-043).
        for (final i in [1, 0, 2, 3, 4, 5, 6, 7]) {
          await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
        }
        await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));
        expect(find.textContaining('Todavía no es el orden correcto'), findsOneWidget);

        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        final peticionesPost = clientePractica.peticiones.where(
          (p) => p.method == 'POST',
        );
        final cuerpo = jsonDecode(peticionesPost.single.body) as Map<String, dynamic>;
        expect(cuerpo['deletreo_correcto'], isFalse);
      },
    );

    testWidgets(
      'RF-38 (T-065): si el guardado falla por un 5xx, muestra el banner de reintentar y no pierde el tiempo ni el mensaje motivacional ya mostrados',
      (tester) async {
        final clientePalabras = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(
          apiClient: ApiClient(httpClient: clientePalabras),
        );
        final practicaService = PracticaService(
          apiClient: ApiClient(httpClient: _ClienteHttpQueFallaSoloEnPost()),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        reloj.avanzar(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 3));
        await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // RF-22 sí funcionó (el GET no falla en este falso) — RF-21/RF-27
        // fallar no debe arrastrar consigo lo que ya funcionó.
        expect(find.textContaining('primer intento'), findsOneWidget);
        // RF-38: un 5xx (a diferencia de SIN_CONEXION, que se encola sin
        // avisar con un botón) muestra el banner de "backend no disponible"
        // con su botón de reintentar — no el SnackBar genérico de cualquier
        // otro error.
        expect(find.byType(MaterialBanner), findsOneWidget);
        expect(find.text('Ocurrió un error inesperado.'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
        expect(find.text('00:03'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-38 (T-065): tocar Reintentar en el banner reenvía el mismo intento (mismo tiempo, oración y deletreo) y esta vez se guarda',
      (tester) async {
        final clientePalabras = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(
          apiClient: ApiClient(httpClient: clientePalabras),
        );
        final clientePractica = _ClienteHttpQuePrimeroFallaLuegoOk();
        final practicaService = PracticaService(
          apiClient: ApiClient(httpClient: clientePractica),
        );
        final reloj = _RelojFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              ahora: reloj.ahora,
              practicaService: practicaService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'A payment for my business.',
        );
        await tester.pump();
        await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
        reloj.avanzar(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));
        await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(
          clientePractica.peticionesPost,
          hasLength(1),
          reason: 'primer intento: falló con 500',
        );
        expect(find.byType(MaterialBanner), findsOneWidget);
        // RF-38: mientras el banner está visible, el formulario sigue ahí
        // debajo — la oración escrita sigue en pantalla, no se limpió.
        expect(find.text('A payment for my business.'), findsOneWidget);

        await _tocar(tester, find.widgetWithText(TextButton, 'Reintentar'));
        await tester.pumpAndSettle();

        expect(
          clientePractica.peticionesPost,
          hasLength(2),
          reason: 'Reintentar debió mandar OTRA petición, no reusar la que falló',
        );
        final segundoIntento =
            jsonDecode(clientePractica.peticionesPost.last.body)
                as Map<String, dynamic>;
        expect(
          segundoIntento['oracion_alumno'],
          'A payment for my business.',
          reason: 'debe reenviar la MISMA oración, sin que nadie tuviera que volver a escribirla',
        );
        expect(segundoIntento['tiempo_segundos'], 5);
        expect(
          find.byType(MaterialBanner),
          findsNothing,
          reason: 'el segundo intento sí se guardó — el banner ya no debe seguir mostrándose',
        );
      },
    );
  });

  group('botón Escúchate (T-048, RF-40)', () {
    testWidgets(
      'aparece una vez en la sección de deletreo y otra en la de oración, ambas mostrando "Escúchate"',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: _GrabadorFalso(),
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'RF-40: si el permiso de micrófono se niega, avisa y no inicia ninguna grabación',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabador = _GrabadorFalso()..permisoConcedido = false;

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabador,
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();

        expect(grabador.permisoSolicitado, isTrue);
        expect(grabador.grabacionIniciada, isFalse);
        expect(
          find.text(
            'Necesitas conceder el permiso de micrófono para usar "Escúchate".',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'RF-40: con permiso concedido, un toque inicia la grabación y cambia a "Detener"',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabador = _GrabadorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabador,
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();

        expect(grabador.grabacionIniciada, isTrue);
        expect(find.widgetWithText(OutlinedButton, 'Detener'), findsOneWidget);
        // La sección de oración (no tocada) sigue en reposo.
        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsOneWidget);
      },
    );

    testWidgets(
      'RF-40: un segundo toque detiene la grabación, la reproduce, y regresa a "Escúchate" al terminar',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabador = _GrabadorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabador,
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();
        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Detener'));
        await tester.pumpAndSettle();

        expect(grabador.reproducido, isTrue);
        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'si falla al iniciar la grabación, avisa sin tronar y regresa a "Escúchate"',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabador = _GrabadorFalso()..errorAlIniciar = Exception('mic ocupado');

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabador,
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('No se pudo iniciar la grabación.'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'si falla al reproducir, avisa sin tronar y de todas formas regresa a "Escúchate" (no se queda atorado)',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabador = _GrabadorFalso()
          ..errorAlReproducir = Exception('fallo simulado');

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabador,
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();
        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Detener'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('No se pudo reproducir la grabación.'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'las dos secciones son independientes: grabar en una no afecta el estado de la otra',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabadorDeletreo = _GrabadorFalso();
        final grabadorOracion = _GrabadorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabadorDeletreo,
              grabadorOracion: grabadorOracion,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();

        expect(grabadorDeletreo.grabacionIniciada, isTrue);
        expect(grabadorOracion.grabacionIniciada, isFalse);
        expect(find.widgetWithText(OutlinedButton, 'Detener'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Escúchate'), findsOneWidget);
      },
    );

    testWidgets('al salir de la pantalla, ambos grabadores se liberan (dispose)', (
      tester,
    ) async {
      final cliente = _ClienteHttpDePrueba(_palabraConAudio);
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
      final grabadorDeletreo = _GrabadorFalso();
      final grabadorOracion = _GrabadorFalso();

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(
            idPalabra: 1,
            token: 'token-de-prueba',
            palabrasService: servicio,
            reproductor: _ReproductorFalso(),
            grabadorDeletreo: grabadorDeletreo,
            grabadorOracion: grabadorOracion,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(_envolver(const SizedBox()));
      await tester.pumpAndSettle();

      expect(grabadorDeletreo.disposed, isTrue);
      expect(grabadorOracion.disposed, isTrue);
    });

    testWidgets(
      'RF-40: usar "Escúchate" de principio a fin no dispara ninguna llamada de red adicional',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final grabador = _GrabadorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
              token: 'token-de-prueba',
              palabrasService: servicio,
              reproductor: _ReproductorFalso(),
              grabadorDeletreo: grabador,
              grabadorOracion: _GrabadorFalso(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ya cargó el detalle de la palabra (1 petición GET) antes de tocar
        // nada de "Escúchate".
        final peticionesAntes = cliente.peticiones.length;

        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Escúchate').first);
        await tester.pumpAndSettle();
        await _tocar(tester, find.widgetWithText(OutlinedButton, 'Detener'));
        await tester.pumpAndSettle();

        // El ciclo completo grabar → detener → reproducir no agregó NINGUNA
        // petición nueva al mismo cliente HTTP que sí usa el resto de la
        // pantalla — prueba directa de que "Escúchate" nunca llama a la red.
        expect(cliente.peticiones.length, peticionesAntes);
      },
    );
  });

  // RF-38 (T-065) + RF-33 (T-062): guardar la práctica con el servidor
  // CAÍDO (la app no llega a ninguna respuesta). El intento se guarda en la
  // cola local (RF-33) y, además, RF-38 exige mensaje claro + opción de
  // reintentar sin perder lo capturado.
  group('servidor caído al guardar la práctica (RF-38, T-065)', () {
    ({
      _ClienteServidorQueSeCaeYVuelve servidor,
      _ColaEnMemoria cola,
      SincronizadorPractica sincronizador,
      _RelojFalso reloj,
      Widget pantalla,
    })
    armar({EstadoConexion dispositivo = EstadoConexion.enLinea}) {
      final servidor = _ClienteServidorQueSeCaeYVuelve();
      final monitor = _MonitorFijo(dispositivo);
      final cola = _ColaEnMemoria();
      PracticaService servicioHaciaElServidor() => PracticaService(
        apiClient: ApiClient(httpClient: servidor, monitorConectividad: monitor),
      );
      final sincronizador = SincronizadorPractica(
        cola: cola,
        token: 'token-de-prueba',
        practicaService: servicioHaciaElServidor(),
        monitorConectividad: monitor,
      );
      addTearDown(sincronizador.dispose);
      final reloj = _RelojFalso();
      final pantalla = PracticaPalabraScreen(
        idPalabra: 1,
        token: 'token-de-prueba',
        palabrasService: PalabrasService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpDePrueba(_palabraConAudio),
          ),
        ),
        reproductor: _ReproductorFalso(),
        ahora: reloj.ahora,
        practicaService: servicioHaciaElServidor(),
        sincronizador: sincronizador,
      );
      return (
        servidor: servidor,
        cola: cola,
        sincronizador: sincronizador,
        reloj: reloj,
        pantalla: pantalla,
      );
    }

    // Deletrea "business" en el orden correcto, escribe una oración y
    // termina la práctica — todo con el servidor ya caído.
    Future<void> practicarYTerminar(WidgetTester tester, _RelojFalso reloj) async {
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await _tocar(tester, find.byKey(ValueKey('ficha-disponible-$i')));
      }
      await _tocar(tester, find.widgetWithText(FilledButton, 'Verificar orden'));
      await tester.enterText(
        find.byType(TextField),
        'I run my own business.',
      );
      await tester.pump();
      await _tocar(tester, find.widgetWithText(FilledButton, 'Iniciar'));
      // DateTime.now() no avanza con pump(): el reloj falso, a mano.
      reloj.avanzar(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await _tocar(tester, find.widgetWithText(FilledButton, 'Terminé'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'con red en el dispositivo: avisa que el SERVIDOR no responde, ofrece Reintentar, conserva deletreo y oración, y el intento queda a salvo en la cola',
      (tester) async {
        final e = armar();
        await tester.pumpWidget(_envolver(e.pantalla));

        await practicarYTerminar(tester, e.reloj);

        expect(find.byType(MaterialBanner), findsOneWidget);
        expect(
          find.textContaining('El servidor no responde en este momento.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Tu práctica ya se guardó en este dispositivo'),
          findsOneWidget,
          reason: 'el aviso no debe parecer "se perdió": el intento está en la cola',
        );
        expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
        // RF-38: lo capturado sigue ahí, en pantalla.
        expect(find.text('I run my own business.'), findsOneWidget);
        expect(find.textContaining('¡Correcto!'), findsOneWidget);
        // RF-33: y a salvo en la cola local.
        expect(e.cola.registros, hasLength(1));
        expect(e.cola.registros.single.oracionAlumno, 'I run my own business.');
        expect(e.cola.registros.single.deletreoCorrecto, isTrue);
        expect(e.cola.registros.single.tiempoSegundos, 3);
      },
    );

    testWidgets(
      'sin red en el dispositivo: el mismo aviso dice que NO HAY CONEXIÓN a internet (no que el servidor no responde)',
      (tester) async {
        final e = armar(dispositivo: EstadoConexion.sinConexion);
        await tester.pumpWidget(_envolver(e.pantalla));

        await practicarYTerminar(tester, e.reloj);

        expect(
          find.textContaining('No tienes conexión a internet.'),
          findsOneWidget,
        );
        expect(find.textContaining('El servidor no responde'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
      },
    );

    testWidgets(
      'Reintentar con el servidor TODAVÍA caído vuelve a avisar (no se queda en silencio) y no duplica el registro en la cola',
      (tester) async {
        final e = armar();
        await tester.pumpWidget(_envolver(e.pantalla));
        await practicarYTerminar(tester, e.reloj);
        final enviosAntes = e.servidor.envios.length;

        await _tocar(tester, find.widgetWithText(TextButton, 'Reintentar'));
        await tester.pumpAndSettle();

        expect(
          e.servidor.envios.length,
          greaterThan(enviosAntes),
          reason: 'Reintentar debe intentar el envío de verdad',
        );
        expect(find.byType(MaterialBanner), findsOneWidget);
        expect(find.textContaining('El servidor no responde'), findsOneWidget);
        expect(e.cola.registros, hasLength(1));
        expect(find.text('I run my own business.'), findsOneWidget);
      },
    );

    testWidgets(
      'Reintentar cuando el servidor VUELVE: manda el MISMO registro (mismo id, oración y deletreo) a /practica/sync, vacía la cola y quita el aviso — sin salir ni reiniciar la pantalla',
      (tester) async {
        final e = armar();
        await tester.pumpWidget(_envolver(e.pantalla));
        await practicarYTerminar(tester, e.reloj);
        final idEnCola = e.cola.registros.single.id;

        // Con el servidor caído también falló la comparación de mejor tiempo
        // (RF-22) y su SnackBar sigue visible: ScaffoldMessenger muestra uno
        // a la vez, así que la confirmación de T-064 quedaría ENCOLADA detrás
        // hasta que ese se cierre. Se limpia para poder verla de inmediato.
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();

        e.servidor.caido = false;
        await _tocar(tester, find.widgetWithText(TextButton, 'Reintentar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final envio = e.servidor.envios.last;
        final enviados =
            (jsonDecode(envio.body) as Map<String, dynamic>)['registros']
                as List<dynamic>;
        expect(enviados, hasLength(1));
        final registro = enviados.single as Map<String, dynamic>;
        expect(registro['id'], idEnCola);
        expect(registro['oracion_alumno'], 'I run my own business.');
        expect(registro['deletreo_correcto'], isTrue);
        expect(registro['tiempo_segundos'], 3);

        expect(e.cola.registros, isEmpty);
        expect(find.byType(MaterialBanner), findsNothing);
        // Misma pantalla, mismo estado: no se reinició ni se fue a otro lado.
        expect(find.byType(PracticaPalabraScreen), findsOneWidget);
        expect(find.text('I run my own business.'), findsOneWidget);
        expect(find.textContaining('¡Correcto!'), findsOneWidget);
        // RF-34 (T-064) confirma la sincronización de forma transitoria.
        expect(find.text('Se sincronizó 1 práctica pendiente.'), findsOneWidget);
      },
    );
  });
}

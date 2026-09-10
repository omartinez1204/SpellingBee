import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/palabras_service.dart';
import 'package:spelling_bee/core/practica_service.dart';
import 'package:spelling_bee/core/reproductor_audio.dart';
import 'package:spelling_bee/screens/practica_palabra_screen.dart';

// Sin librería de mocking: un http.Client falso que regresa una respuesta
// fija, igual de simple que el _AlmacenDePruebaEnMemoria de
// auth_controller_test.dart pero para el cliente HTTP en vez del storage.
class _ClienteHttpDePrueba extends http.BaseClient {
  _ClienteHttpDePrueba(this._respuesta, {this.statusCode = 200});

  final Map<String, dynamic> _respuesta;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final cuerpo = utf8.encode(jsonEncode(_respuesta));
    return http.StreamedResponse(
      Stream.value(cuerpo),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
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

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        expect(find.widgetWithText(FilledButton, 'Terminé'), findsOneWidget);

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

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          reloj.avanzar(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('00:03'), findsOneWidget);

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

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
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

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        // 3s < los 10s de mejor marca previa: debe contar como mejora.
        for (var i = 0; i < 3; i++) {
          reloj.avanzar(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Terminé'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Mejoraste'), findsOneWidget);
        expect(find.textContaining('00:10'), findsOneWidget);
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

        await tester.tap(find.widgetWithText(FilledButton, 'Iniciar'));
        await tester.pump();
        reloj.avanzar(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 3));
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
}

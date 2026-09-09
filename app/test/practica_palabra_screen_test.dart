import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/palabras_service.dart';
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
  final List<String> urlsReproducidas = [];
  int vecesPausado = 0;
  int vecesReanudado = 0;
  int vecesDetenido = 0;
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

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controlador.close();
  }

  /// RF-17: simula que el audio llegó solo a su fin (sin que nadie haya
  /// tocado "detener"), tal como haría ReproductorAudioJustAudio al ver
  /// ProcessingState.completed.
  void simularFinNatural() => _controlador.add(EstadoAudio.detenido);
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
      'RF-16: el botón de detener solo aparece mientras hay algo que detener, y al presionarlo resetea el ícono',
      (tester) async {
        final cliente = _ClienteHttpDePrueba(_palabraConAudio);
        final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));
        final reproductor = _ReproductorFalso();

        await tester.pumpWidget(
          _envolver(
            PracticaPalabraScreen(
              idPalabra: 1,
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
  });
}

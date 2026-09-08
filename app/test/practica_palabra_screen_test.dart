import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/palabras_service.dart';
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

Widget _envolver(Widget child) =>
    MaterialApp(home: child, debugShowCheckedModeBanner: false);

void main() {
  testWidgets(
    'muestra de inmediato la palabra y el ícono de audio, sin significado ni oración visibles',
    (tester) async {
      final cliente = _ClienteHttpDePrueba({
        'id': 1,
        'texto': 'business',
        'significado_es': 'negocio',
        'oracion_ejemplo': 'This is a business.',
        'url_audio': '/assets/audios/1.mp3',
      });
      final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

      await tester.pumpWidget(
        _envolver(
          PracticaPalabraScreen(idPalabra: 1, palabrasService: servicio),
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
    final cliente = _ClienteHttpDePrueba({
      'id': 1,
      'texto': 'business',
      'significado_es': 'negocio',
      'oracion_ejemplo': 'This is a business.',
      'url_audio': null,
    });
    final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

    await tester.pumpWidget(
      _envolver(PracticaPalabraScreen(idPalabra: 1, palabrasService: servicio)),
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
    final cliente = _ClienteHttpDePrueba({
      'id': 1,
      'texto': 'business',
      'significado_es': 'negocio',
      'oracion_ejemplo': 'This is a business.',
      'url_audio': null,
    });
    final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

    await tester.pumpWidget(
      _envolver(PracticaPalabraScreen(idPalabra: 1, palabrasService: servicio)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver ejemplo'));
    await tester.pump();

    expect(find.text('This is a business.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Ver ejemplo'), findsNothing);
  });

  testWidgets('el ícono de audio no reproduce nada, solo avisa que es una fase posterior', (
    tester,
  ) async {
    final cliente = _ClienteHttpDePrueba({
      'id': 1,
      'texto': 'business',
      'significado_es': null,
      'oracion_ejemplo': null,
      'url_audio': null,
    });
    final servicio = PalabrasService(apiClient: ApiClient(httpClient: cliente));

    await tester.pumpWidget(
      _envolver(PracticaPalabraScreen(idPalabra: 1, palabrasService: servicio)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();

    expect(
      find.text('La reproducción de audio llega en una fase posterior.'),
      findsOneWidget,
    );
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
        _envolver(PracticaPalabraScreen(idPalabra: 1, palabrasService: servicio)),
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
        PracticaPalabraScreen(idPalabra: 999999, palabrasService: servicio),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No existe una palabra con ese id.'), findsOneWidget);
  });
}

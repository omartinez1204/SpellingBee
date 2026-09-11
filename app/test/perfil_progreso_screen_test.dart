import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/insignias_service.dart';
import 'package:spelling_bee/core/niveles_service.dart';
import 'package:spelling_bee/screens/perfil_progreso_screen.dart';

// T-047 (RF-24). Igual que _ClienteHttpDePrueba en
// practica_palabra_screen_test.dart: un http.Client falso que distingue por
// RUTA (no solo por método), porque esta pantalla llama a la vez a
// GET /niveles y GET /progreso/insignias, cada uno con su propia forma de
// respuesta.
class _ClienteHttpPorRuta extends http.BaseClient {
  _ClienteHttpPorRuta(this._respuestasPorRuta);

  final Map<String, dynamic> _respuestasPorRuta;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final cuerpoJson = _respuestasPorRuta[request.url.path];
    if (cuerpoJson == null) {
      throw StateError('Ruta no configurada en la prueba: ${request.url.path}');
    }
    final cuerpo = utf8.encode(jsonEncode(cuerpoJson));
    return http.StreamedResponse(
      Stream.value(cuerpo),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _ClienteHttpQueFalla extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
  }
}

const _tresNiveles = [
  {'id': 1, 'nombre': 'Fácil', 'orden': 1},
  {'id': 2, 'nombre': 'Intermedio', 'orden': 2},
  {'id': 3, 'nombre': 'Difícil', 'orden': 3},
];

Widget _envolver(Widget child) =>
    MaterialApp(home: child, debugShowCheckedModeBanner: false);

void main() {
  group('PerfilProgresoScreen (RF-24, T-047)', () {
    testWidgets('muestra un indicador de carga mientras llegan los datos', (
      tester,
    ) async {
      final nivelesService = NivelesService(
        apiClient: ApiClient(
          httpClient: _ClienteHttpPorRuta({'/niveles': _tresNiveles}),
        ),
      );
      final insigniasService = InsigniasService(
        apiClient: ApiClient(
          httpClient: _ClienteHttpPorRuta({'/progreso/insignias': []}),
        ),
      );

      await tester.pumpWidget(
        _envolver(
          PerfilProgresoScreen(
            token: 'token-de-prueba',
            nivelesService: nivelesService,
            insigniasService: insigniasService,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'muestra los 3 niveles, marcando como ganado solo el que tiene insignia',
      (tester) async {
        final nivelesService = NivelesService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpPorRuta({'/niveles': _tresNiveles}),
          ),
        );
        final insigniasService = InsigniasService(
          apiClient: ApiClient(
            httpClient: _ClienteHttpPorRuta({
              '/progreso/insignias': [
                {
                  'id_nivel': 2,
                  'nombre_nivel': 'Intermedio',
                  'fecha_otorgada': '2026-01-01T00:00:00.000Z',
                },
              ],
            }),
          ),
        );

        await tester.pumpWidget(
          _envolver(
            PerfilProgresoScreen(
              token: 'token-de-prueba',
              nivelesService: nivelesService,
              insigniasService: insigniasService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Fácil'), findsOneWidget);
        expect(find.text('Intermedio'), findsOneWidget);
        expect(find.text('Difícil'), findsOneWidget);
        expect(find.text('Insignia obtenida'), findsOneWidget);
        expect(
          find.text('Todavía no completas este nivel al 100%'),
          findsNWidgets(2),
        );
      },
    );

    testWidgets('sin ninguna insignia ganada, ningún nivel aparece marcado', (
      tester,
    ) async {
      final nivelesService = NivelesService(
        apiClient: ApiClient(
          httpClient: _ClienteHttpPorRuta({'/niveles': _tresNiveles}),
        ),
      );
      final insigniasService = InsigniasService(
        apiClient: ApiClient(
          httpClient: _ClienteHttpPorRuta({'/progreso/insignias': []}),
        ),
      );

      await tester.pumpWidget(
        _envolver(
          PerfilProgresoScreen(
            token: 'token-de-prueba',
            nivelesService: nivelesService,
            insigniasService: insigniasService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Insignia obtenida'), findsNothing);
      expect(
        find.text('Todavía no completas este nivel al 100%'),
        findsNWidgets(3),
      );
    });

    testWidgets('si falla la carga, muestra un mensaje de error sin tronar', (
      tester,
    ) async {
      final nivelesService = NivelesService(
        apiClient: ApiClient(httpClient: _ClienteHttpQueFalla()),
      );
      final insigniasService = InsigniasService(
        apiClient: ApiClient(httpClient: _ClienteHttpQueFalla()),
      );

      await tester.pumpWidget(
        _envolver(
          PerfilProgresoScreen(
            token: 'token-de-prueba',
            nivelesService: nivelesService,
            insigniasService: insigniasService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // _ClienteHttpQueFalla regresa 500 con cuerpo "{}" (sin error.code ni
      // error.message) — ApiClient lo traduce al mensaje genérico de
      // ApiException, que la pantalla sí sabe mostrar (branch `is ApiException`).
      expect(find.text('Ocurrió un error inesperado.'), findsOneWidget);
    });
  });
}

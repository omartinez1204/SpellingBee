import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/admin_alumnos_service.dart';
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/detalle_alumno_controller.dart';
import 'package:spelling_bee/core/niveles_service.dart';
import 'package:spelling_bee/screens/detalle_alumno_screen.dart';

// Simula lo mínimo de GET /niveles y GET /admin/alumnos/:id (T-051, RF-29),
// con los filtros de T-052 (RF-30). Cada intento de prueba trae "id_nivel"
// SOLO para que este simulador sepa filtrar por nivel — igual que el
// backend real, el campo nunca viaja en el JSON de respuesta (RF-29 solo
// pide palabra/tiempo/oración).
class _BackendSimulado {
  _BackendSimulado({
    List<Map<String, dynamic>>? intentosIniciales,
    this.carreraAlumno = 'Ingeniería en Desarrollo de Software',
    this.semestreAlumno = 5,
  }) : _intentos = intentosIniciales ?? [];

  final List<Map<String, dynamic>> _intentos;
  final String carreraAlumno;
  final int semestreAlumno;

  http.Response responder(http.BaseRequest request) {
    final metodo = request.method;
    final ruta = request.url.path;
    final query = request.url.queryParameters;

    if (metodo == 'GET' && ruta == '/niveles') {
      return _json(200, [
        {'id': 1, 'nombre': 'Fácil', 'orden': 1},
        {'id': 2, 'nombre': 'Intermedio', 'orden': 2},
        {'id': 3, 'nombre': 'Difícil', 'orden': 3},
      ]);
    }

    if (metodo == 'GET' && ruta.startsWith('/admin/alumnos/')) {
      final pagina = int.parse(query['pagina'] ?? '1');
      final limite = int.parse(query['limite'] ?? '20');
      final nivel = query['nivel'] != null ? int.parse(query['nivel']!) : null;
      final carrera = query['carrera'];
      final semestre = query['semestre'] != null
          ? int.parse(query['semestre']!)
          : null;

      // Mismo criterio que el backend real (T-052): si el alumno fijado por
      // :id no cumple carrera/semestre, el resultado es vacío — nivel
      // angosta los INTENTOS, no decide si el alumno "existe".
      final cumpleAlumno =
          (carrera == null || carrera == carreraAlumno) &&
          (semestre == null || semestre == semestreAlumno);

      final filtrados = !cumpleAlumno
          ? <Map<String, dynamic>>[]
          : _intentos
                .where((it) => nivel == null || it['id_nivel'] == nivel)
                .toList();

      final inicio = (pagina - 1) * limite;
      final fin = (inicio + limite).clamp(0, filtrados.length);
      final filas = inicio >= filtrados.length
          ? <Map<String, dynamic>>[]
          : filtrados.sublist(inicio, fin);

      return _json(200, {
        // id_nivel es solo para este simulador — nunca viaja en la
        // respuesta real (RF-29).
        'intentos': filas
            .map(
              (it) => {
                'id_palabra': it['id_palabra'],
                'palabra': it['palabra'],
                'tiempo_segundos': it['tiempo_segundos'],
                'oracion_alumno': it['oracion_alumno'],
              },
            )
            .toList(),
        'total': filtrados.length,
        'pagina': pagina,
        'limite': limite,
        'total_paginas': (filtrados.length / limite).ceil().clamp(1, 1 << 30),
      });
    }

    throw StateError('Ruta no simulada en la prueba: $metodo $ruta');
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

/// Falla la primera petición, luego funciona normal — para probar
/// "Reintentar" (mismo patrón que admin_catalogo_screen_test.dart).
class _ClienteConFalloInicial extends http.BaseClient {
  _ClienteConFalloInicial(this._backend);

  final _BackendSimulado _backend;
  bool _yaFallo = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_yaFallo) {
      _yaFallo = true;
      throw Exception('falla de red simulada');
    }
    final respuesta = _backend.responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(respuesta.body)),
      respuesta.statusCode,
      headers: respuesta.headers,
    );
  }
}

/// RF-38 (T-065): mientras [fallarSegundaPagina] sea true, toda petición de
/// la página 2 (carga incremental por scroll) responde 500; lo demás
/// funciona normal. Interruptor y no "falla una sola vez": el listener del
/// scroll puede volver a disparar la carga varias veces seguidas.
class _ClienteQueFallaLaSegundaPagina extends http.BaseClient {
  _ClienteQueFallaLaSegundaPagina(this._backend);

  final _BackendSimulado _backend;
  bool fallarSegundaPagina = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (fallarSegundaPagina && request.url.queryParameters['pagina'] == '2') {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
    }
    final respuesta = _backend.responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(respuesta.body)),
      respuesta.statusCode,
      headers: respuesta.headers,
    );
  }
}

DetalleAlumnoController _controladorDePrueba(http.Client cliente) {
  return DetalleAlumnoController(
    token: 'token-de-prueba',
    idAlumno: 1,
    adminAlumnosService: AdminAlumnosService(
      apiClient: ApiClient(httpClient: cliente),
    ),
    nivelesService: NivelesService(apiClient: ApiClient(httpClient: cliente)),
  );
}

Widget _envolver(Widget child) =>
    MaterialApp(home: child, debugShowCheckedModeBanner: false);

void main() {
  testWidgets(
    'RF-29: lista palabra, tiempo formateado y oración de cada intento',
    (tester) async {
      final backend = _BackendSimulado(
        intentosIniciales: [
          {
            'id_palabra': 1,
            'palabra': 'business',
            'tiempo_segundos': 75,
            'oracion_alumno': 'This is my business sentence.',
            'id_nivel': 1,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Ana García López',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana García López'), findsOneWidget);
      expect(find.text('business'), findsOneWidget);
      expect(find.text('This is my business sentence.'), findsOneWidget);
      // 75s = 01:15 (RF-18, mismo formato mm:ss ya usado en toda la app).
      expect(find.text('01:15'), findsOneWidget);
    },
  );

  testWidgets(
    'RF-27: no muestra el resultado de deletreo — RF-29 solo pide palabra/tiempo/oración',
    (tester) async {
      final backend = _BackendSimulado(
        intentosIniciales: [
          {
            'id_palabra': 1,
            'palabra': 'business',
            'tiempo_segundos': 10,
            'oracion_alumno': 'x',
            'id_nivel': 1,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Alumno',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('correcto'), findsNothing);
      expect(find.textContaining('incorrecto'), findsNothing);
    },
  );

  testWidgets(
    'sin ningún intento, muestra el mensaje correspondiente (no es un error)',
    (tester) async {
      final cliente = _ClienteHttpDePrueba(_BackendSimulado());

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Alumno Sin Práctica',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Este alumno todavía no tiene ningún intento de práctica registrado.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('si falla la carga inicial, muestra el error y permite reintentar', (
    tester,
  ) async {
    final backend = _BackendSimulado();
    final cliente = _ClienteConFalloInicial(backend);

    await tester.pumpWidget(
      _envolver(
        DetalleAlumnoScreen(
          token: 'token-de-prueba',
          idAlumno: 1,
          nombreAlumno: 'Alumno',
          controller: _controladorDePrueba(cliente),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Este alumno todavía no tiene ningún intento de práctica registrado.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'paginación: hacer scroll cerca del final carga la siguiente página automáticamente',
    (tester) async {
      final intentos = List.generate(
        25,
        (i) => {
          'id_palabra': i + 1,
          'palabra': 'palabra-$i',
          'tiempo_segundos': 10,
          'oracion_alumno': 'x',
          'id_nivel': 1,
        },
      );
      final backend = _BackendSimulado(intentosIniciales: intentos);
      final cliente = _ClienteHttpDePrueba(backend);

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Alumno',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('palabra-0'), findsOneWidget);
      expect(find.text('palabra-20'), findsNothing);

      final lista = find.byType(ListView);
      for (var i = 0; i < 15 && find.text('palabra-20').evaluate().isEmpty; i++) {
        await tester.drag(lista, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('palabra-20'), findsOneWidget);
    },
  );

  testWidgets(
    'RF-38 (T-065): si la carga incremental falla por un 5xx, avisa con el banner (antes fallaba en silencio) y Reintentar carga la página faltante',
    (tester) async {
      final intentos = List.generate(
        25,
        (i) => {
          'id_palabra': i + 1,
          'palabra': 'palabra-$i',
          'tiempo_segundos': 10,
          'oracion_alumno': 'x',
          'id_nivel': 1,
        },
      );
      final cliente = _ClienteQueFallaLaSegundaPagina(
        _BackendSimulado(intentosIniciales: intentos),
      );

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Alumno',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lista = find.byType(ListView);
      for (var i = 0; i < 6; i++) {
        await tester.drag(lista, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('Ocurrió un error inesperado.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      cliente.fallarSegundaPagina = false;
      await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsNothing);
      for (
        var i = 0;
        i < 10 && find.text('palabra-24').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(lista, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        find.text('palabra-24'),
        findsOneWidget,
        reason: 'la página 2 (intentos 20 a 24) llegó tras Reintentar',
      );
    },
  );

  testWidgets(
    'RF-30 (T-052): también en el detalle — nivel angosta los intentos mostrados',
    (tester) async {
      final backend = _BackendSimulado(
        intentosIniciales: [
          {
            'id_palabra': 1,
            'palabra': 'facil-1',
            'tiempo_segundos': 10,
            'oracion_alumno': 'x',
            'id_nivel': 1,
          },
          {
            'id_palabra': 2,
            'palabra': 'intermedio-1',
            'tiempo_segundos': 10,
            'oracion_alumno': 'x',
            'id_nivel': 2,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Alumno',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('facil-1'), findsOneWidget);
      expect(find.text('intermedio-1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtro-nivel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intermedio').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('facil-1'), findsNothing);
      expect(find.text('intermedio-1'), findsOneWidget);
    },
  );

  testWidgets(
    'RF-30 (T-052): también en el detalle — carrera/semestre que no coinciden con el alumno dan vacío, no error',
    (tester) async {
      final backend = _BackendSimulado(
        carreraAlumno: 'Ingeniería en Desarrollo de Software',
        semestreAlumno: 5,
        intentosIniciales: [
          {
            'id_palabra': 1,
            'palabra': 'facil-1',
            'tiempo_segundos': 10,
            'oracion_alumno': 'x',
            'id_nivel': 1,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);

      await tester.pumpWidget(
        _envolver(
          DetalleAlumnoScreen(
            token: 'token-de-prueba',
            idAlumno: 1,
            nombreAlumno: 'Alumno',
            controller: _controladorDePrueba(cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('facil-1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtro-carrera')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Licenciatura en MiPymes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('facil-1'), findsNothing);
      expect(
        find.text(
          'Ningún intento de este alumno cumple los filtros seleccionados.',
        ),
        findsOneWidget,
      );
      // No es un error: no aparece "Reintentar".
      expect(find.widgetWithText(FilledButton, 'Reintentar'), findsNothing);
    },
  );
}

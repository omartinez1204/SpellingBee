import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/admin_alumnos_service.dart';
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/auth_controller.dart';
import 'package:spelling_bee/core/niveles_service.dart';
import 'package:spelling_bee/core/seguimiento_alumnos_controller.dart';
import 'package:spelling_bee/screens/seguimiento_alumnos_screen.dart';

// Mismo patrón que admin_catalogo_screen_test.dart.
class _AlmacenDePruebaEnMemoria extends FlutterSecureStorage {
  final Map<String, String> _valores = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _valores[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _valores.remove(key);
    } else {
      _valores[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _valores.remove(key);
  }
}

String _jwtDePrueba(String rol) {
  String segmento(Map<String, Object?> mapa) =>
      base64Url.encode(utf8.encode(jsonEncode(mapa))).replaceAll('=', '');
  final header = segmento({'alg': 'HS256', 'typ': 'JWT'});
  final payload = segmento({
    'sub': 1,
    'rol': rol,
    'debe_cambiar_contrasena': false,
    'exp':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
  });
  return '$header.$payload.firma-no-verificada-en-la-prueba';
}

Future<AuthController> _authConSesion(String rol, http.Client cliente) async {
  final storage = _AlmacenDePruebaEnMemoria();
  await storage.write(key: 'jwt_token', value: _jwtDePrueba(rol));
  final auth = AuthController(
    apiClient: ApiClient(httpClient: cliente),
    storage: storage,
  );
  await auth.cargarSesionGuardada();
  return auth;
}

SeguimientoAlumnosController _controladorDePrueba(
  AuthController auth,
  http.Client cliente,
) {
  return SeguimientoAlumnosController(
    token: auth.sesion!.token,
    adminAlumnosService: AdminAlumnosService(
      apiClient: ApiClient(httpClient: cliente),
    ),
    nivelesService: NivelesService(apiClient: ApiClient(httpClient: cliente)),
  );
}

// Simula lo mínimo de GET /niveles, GET /admin/alumnos (T-050/T-052) y
// GET /admin/alumnos/:id (T-051) para que la pantalla y su navegación al
// detalle funcionen sin red real.
class _BackendSimulado {
  _BackendSimulado({List<Map<String, dynamic>>? alumnosIniciales})
    : _alumnos = alumnosIniciales ?? [];

  final List<Map<String, dynamic>> _alumnos;

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

    if (metodo == 'GET' && ruta == '/admin/alumnos') {
      final pagina = int.parse(query['pagina'] ?? '1');
      final limite = int.parse(query['limite'] ?? '20');
      final nivel = query['nivel'] != null ? int.parse(query['nivel']!) : null;
      final carrera = query['carrera'];
      final semestre = query['semestre'] != null
          ? int.parse(query['semestre']!)
          : null;

      // Mismo criterio que el backend real (T-052): carrera/semestre
      // filtran QUÉ alumnos aparecen; nivel angosta el avance mostrado, sin
      // excluir a nadie.
      final filtrados = _alumnos.where((a) {
        if (carrera != null && a['carrera'] != carrera) return false;
        if (semestre != null && a['semestre'] != semestre) return false;
        return true;
      }).toList();

      final inicio = (pagina - 1) * limite;
      final fin = (inicio + limite).clamp(0, filtrados.length);
      final filas = inicio >= filtrados.length
          ? <Map<String, dynamic>>[]
          : filtrados.sublist(inicio, fin);

      final alumnosRespuesta = filas.map((a) {
        final avanceCompleto = a['avance'] as List<dynamic>;
        final avanceFiltrado = nivel == null
            ? avanceCompleto
            : avanceCompleto
                  .where((av) => (av as Map)['id_nivel'] == nivel)
                  .toList();
        return {...a, 'avance': avanceFiltrado};
      }).toList();

      return _json(200, {
        'alumnos': alumnosRespuesta,
        'total': filtrados.length,
        'pagina': pagina,
        'limite': limite,
        'total_paginas': (filtrados.length / limite).ceil().clamp(1, 1 << 30),
      });
    }

    if (metodo == 'GET' && ruta.startsWith('/admin/alumnos/')) {
      // Suficiente para que la navegación al detalle no truene — el
      // contenido del detalle en sí se prueba en
      // detalle_alumno_screen_test.dart.
      return _json(200, {
        'intentos': [],
        'total': 0,
        'pagina': 1,
        'limite': 20,
        'total_paginas': 1,
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

/// Falla la primera petición a /admin/alumnos, luego funciona normal — para
/// probar "Reintentar" (mismo patrón que admin_catalogo_screen_test.dart).
class _ClienteConFalloInicial extends http.BaseClient {
  _ClienteConFalloInicial(this._backend);

  final _BackendSimulado _backend;
  bool _yaFallo = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/admin/alumnos' && !_yaFallo) {
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

Map<String, dynamic> _alumno({
  required int id,
  required String matricula,
  required String nombre,
  String carrera = 'Ingeniería en Desarrollo de Software',
  int semestre = 5,
  List<Map<String, dynamic>>? avance,
}) {
  return {
    'id': id,
    'matricula': matricula,
    'nombre': nombre,
    'apellido_paterno': 'Apellido',
    'apellido_materno': 'DePrueba',
    'carrera': carrera,
    'semestre': semestre,
    'avance':
        avance ??
        [
          {'id_nivel': 1, 'palabras_practicadas': 0},
          {'id_nivel': 2, 'palabras_practicadas': 0},
          {'id_nivel': 3, 'palabras_practicadas': 0},
        ],
  };
}

Widget _envolver(Widget child) =>
    MaterialApp(home: child, debugShowCheckedModeBanner: false);

void main() {
  testWidgets(
    'con sesión de alumno, muestra el aviso de "solo profesores" y no carga nada',
    (tester) async {
      final cliente = _ClienteHttpDePrueba(_BackendSimulado());
      final auth = await _authConSesion('alumno', cliente);

      await tester.pumpWidget(
        _envolver(SeguimientoAlumnosScreen(authController: auth)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Esta pantalla es exclusiva para profesores.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'con sesión de profesor, lista a los alumnos con su avance por nivel',
    (tester) async {
      final backend = _BackendSimulado(
        alumnosIniciales: [
          _alumno(
            id: 101,
            matricula: 'A00123456',
            nombre: 'Ana',
            avance: [
              {'id_nivel': 1, 'palabras_practicadas': 3},
              {'id_nivel': 2, 'palabras_practicadas': 1},
              {'id_nivel': 3, 'palabras_practicadas': 0},
            ],
          ),
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          SeguimientoAlumnosScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana Apellido DePrueba'), findsOneWidget);
      expect(
        find.textContaining('A00123456'),
        findsOneWidget,
      );
      expect(find.text('Fácil: 3'), findsOneWidget);
      expect(find.text('Intermedio: 1'), findsOneWidget);
      expect(find.text('Difícil: 0'), findsOneWidget);
    },
  );

  testWidgets('sin ningún alumno registrado, muestra el mensaje correspondiente', (
    tester,
  ) async {
    final cliente = _ClienteHttpDePrueba(_BackendSimulado());
    final auth = await _authConSesion('profesor', cliente);

    await tester.pumpWidget(
      _envolver(
        SeguimientoAlumnosScreen(
          authController: auth,
          controller: _controladorDePrueba(auth, cliente),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todavía no hay alumnos registrados.'), findsOneWidget);
  });

  testWidgets('si falla la carga inicial, muestra el error y permite reintentar', (
    tester,
  ) async {
    final backend = _BackendSimulado();
    final cliente = _ClienteConFalloInicial(backend);
    final auth = await _authConSesion('profesor', cliente);

    await tester.pumpWidget(
      _envolver(
        SeguimientoAlumnosScreen(
          authController: auth,
          controller: _controladorDePrueba(auth, cliente),
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

    expect(find.text('Todavía no hay alumnos registrados.'), findsOneWidget);
  });

  testWidgets(
    'RF-30: filtro de nivel angosta el avance mostrado a solo ese nivel',
    (tester) async {
      final backend = _BackendSimulado(
        alumnosIniciales: [
          _alumno(
            id: 1,
            matricula: 'A1',
            nombre: 'Uno',
            avance: [
              {'id_nivel': 1, 'palabras_practicadas': 5},
              {'id_nivel': 2, 'palabras_practicadas': 2},
              {'id_nivel': 3, 'palabras_practicadas': 1},
            ],
          ),
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      // Ver el pie de la lista de opciones del dropdown de nivel (4
      // elementos: "Todos" + 3 niveles) requiere más alto que los 600px por
      // defecto de las pruebas.
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _envolver(
          SeguimientoAlumnosScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fácil: 5'), findsOneWidget);
      expect(find.text('Intermedio: 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtro-nivel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intermedio').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Fácil: 5'), findsNothing);
      expect(find.text('Intermedio: 2'), findsOneWidget);
    },
  );

  testWidgets(
    'RF-30: combinar carrera y semestre excluye a quien no cumple ambos',
    (tester) async {
      final backend = _BackendSimulado(
        alumnosIniciales: [
          _alumno(
            id: 1,
            matricula: 'MATCH',
            nombre: 'Coincide',
            carrera: 'Ingeniería en Desarrollo de Software',
            semestre: 3,
          ),
          _alumno(
            id: 2,
            matricula: 'OTRA-CARRERA',
            nombre: 'OtraCarrera',
            carrera: 'Licenciatura en MiPymes',
            semestre: 3,
          ),
          _alumno(
            id: 3,
            matricula: 'OTRO-SEMESTRE',
            nombre: 'OtroSemestre',
            carrera: 'Ingeniería en Desarrollo de Software',
            semestre: 7,
          ),
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      // Las 3 tarjetas (con matrícula/carrera/semestre + chips de avance)
      // no caben en los 600px de alto del viewport por defecto de las
      // pruebas — se necesita ver las 3 a la vez para comparar antes/
      // después del filtro, así que se agranda el lienzo de la prueba en
      // vez de desplazarse (que además cambiaría cuál tarjeta está "de
      // primera" para cada aserción).
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _envolver(
          SeguimientoAlumnosScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coincide Apellido DePrueba'), findsOneWidget);
      expect(find.text('OtraCarrera Apellido DePrueba'), findsOneWidget);
      expect(find.text('OtroSemestre Apellido DePrueba'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtro-carrera')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Ingeniería en Desarrollo de Software').last,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filtro-semestre')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Coincide Apellido DePrueba'), findsOneWidget);
      expect(find.text('OtraCarrera Apellido DePrueba'), findsNothing);
      expect(find.text('OtroSemestre Apellido DePrueba'), findsNothing);
    },
  );

  testWidgets(
    'sin ningún alumno registrado tras aplicar filtros, el mensaje distingue "filtros" de "sin alumnos"',
    (tester) async {
      final backend = _BackendSimulado(
        alumnosIniciales: [
          _alumno(
            id: 1,
            matricula: 'A1',
            nombre: 'Uno',
            carrera: 'Ingeniería en Agroalimentos',
          ),
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          SeguimientoAlumnosScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filtro-carrera')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Licenciatura en MiPymes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar filtros'));
      await tester.pumpAndSettle();

      expect(
        find.text('Ningún alumno cumple los filtros seleccionados.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Limpiar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Uno Apellido DePrueba'), findsOneWidget);
    },
  );

  testWidgets(
    'paginación: hacer scroll cerca del final carga la siguiente página automáticamente',
    (tester) async {
      final alumnos = List.generate(
        25,
        (i) => _alumno(id: i + 1, matricula: 'M$i', nombre: 'alumno-$i'),
      );
      final backend = _BackendSimulado(alumnosIniciales: alumnos);
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          SeguimientoAlumnosScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('alumno-0 '), findsOneWidget);
      expect(find.textContaining('alumno-20 '), findsNothing);

      final lista = find.byType(ListView);
      for (
        var i = 0;
        i < 15 && find.textContaining('alumno-20 ').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(lista, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.textContaining('alumno-20 '), findsOneWidget);
    },
  );

  testWidgets(
    'RF-38 (T-065): si la carga incremental falla por un 5xx, avisa con el banner (antes fallaba en silencio) y Reintentar carga la página faltante',
    (tester) async {
      final alumnos = List.generate(
        25,
        (i) => _alumno(id: i + 1, matricula: 'M$i', nombre: 'alumno-$i'),
      );
      final cliente = _ClienteQueFallaLaSegundaPagina(
        _BackendSimulado(alumnosIniciales: alumnos),
      );
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          SeguimientoAlumnosScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Las filas de esta pantalla son más altas que las del catálogo: se
      // arrastra hasta que el listener del scroll dispare la carga (y falle).
      final lista = find.byType(ListView);
      for (
        var i = 0;
        i < 15 && find.byType(MaterialBanner).evaluate().isEmpty;
        i++
      ) {
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
        i < 10 && find.textContaining('alumno-24 ').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(lista, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        find.textContaining('alumno-24 '),
        findsOneWidget,
        reason: 'la página 2 (alumnos 20 a 24) llegó tras Reintentar',
      );
    },
  );

  testWidgets('tocar un alumno navega a su pantalla de detalle', (
    tester,
  ) async {
    final backend = _BackendSimulado(
      alumnosIniciales: [_alumno(id: 55, matricula: 'A55', nombre: 'Quintana')],
    );
    final cliente = _ClienteHttpDePrueba(backend);
    final auth = await _authConSesion('profesor', cliente);

    await tester.pumpWidget(
      _envolver(
        SeguimientoAlumnosScreen(
          authController: auth,
          controller: _controladorDePrueba(auth, cliente),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quintana Apellido DePrueba'));
    await tester.pumpAndSettle();

    // El AppBar de la pantalla de detalle usa el nombre ya conocido, sin
    // pedirlo de nuevo al backend.
    expect(find.text('Quintana Apellido DePrueba'), findsOneWidget);
    expect(
      find.text('Este alumno todavía no tiene ningún intento de práctica registrado.'),
      findsOneWidget,
    );
  });
}

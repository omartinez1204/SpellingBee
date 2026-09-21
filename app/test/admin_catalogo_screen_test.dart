import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/admin_catalogo_controller.dart';
import 'package:spelling_bee/core/admin_palabras_service.dart';
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/auth_controller.dart';
import 'package:spelling_bee/core/localizacion.dart';
import 'package:spelling_bee/core/niveles_service.dart';
import 'package:spelling_bee/screens/admin_catalogo_screen.dart';

import 'helpers/textos_espanol.dart';

// Mismo patrón que auth_controller_test.dart: un storage en memoria para no
// depender de flutter_secure_storage (no disponible fuera de un dispositivo)
// y un JWT con forma válida para precargar una sesión ya iniciada, sin pasar
// por POST /auth/login en cada prueba.
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

/// Arma un AuthController con una sesión del rol pedido ya cargada, sin
/// pasar por POST /auth/login. El http.Client que reciben tanto este
/// AuthController como el AdminCatalogoController de cada prueba debe ser el
/// mismo cliente falso — si se omite en cualquiera de los dos, ese lado cae
/// al http.Client real por default y la prueba truena contra la red
/// bloqueada del entorno de test (justo el bug que esto evita).
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

AdminCatalogoController _controladorDePrueba(
  AuthController auth,
  http.Client cliente,
) {
  return AdminCatalogoController(
    token: auth.sesion!.token,
    palabrasService: AdminPalabrasService(
      apiClient: ApiClient(httpClient: cliente),
    ),
    nivelesService: NivelesService(apiClient: ApiClient(httpClient: cliente)),
  );
}

// Simula lo mínimo necesario del backend real (T-020, T-024, T-025) para que
// la pantalla haga sus llamadas normales sin red de verdad. Mantiene un
// "catálogo" mutable en memoria para que crear/editar/ocultar/subir audio se
// reflejen igual que en el backend real dentro de una misma prueba.
class _BackendSimulado {
  _BackendSimulado({List<Map<String, dynamic>>? palabrasIniciales})
    : _palabras = palabrasIniciales ?? [];

  final List<Map<String, dynamic>> _palabras;
  int _siguienteId = 1000;

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

    if (metodo == 'GET' && ruta == '/admin/palabras') {
      final pagina = int.parse(query['pagina'] ?? '1');
      final limite = int.parse(query['limite'] ?? '20');
      final inicio = (pagina - 1) * limite;
      final fin = (inicio + limite).clamp(0, _palabras.length);
      final filas = inicio >= _palabras.length
          ? <Map<String, dynamic>>[]
          : _palabras.sublist(inicio, fin);
      return _json(200, {
        'palabras': filas,
        'total': _palabras.length,
        'pagina': pagina,
        'limite': limite,
        'total_paginas': (_palabras.length / limite).ceil().clamp(1, 1 << 30),
      });
    }

    if (metodo == 'POST' && ruta == '/admin/palabras') {
      final cuerpo = jsonDecode((request as http.Request).body) as Map;
      final nueva = {
        'id': _siguienteId++,
        'texto': cuerpo['texto'],
        'id_nivel': cuerpo['id_nivel'],
        'significado_es': cuerpo['significado_es'],
        'oracion_ejemplo': cuerpo['oracion_ejemplo'],
        'url_audio': null,
        'completa': false,
        'oculta': false,
      };
      _palabras.insert(0, nueva);
      return _json(201, nueva);
    }

    if (metodo == 'PATCH' && ruta.endsWith('/ocultar')) {
      final id = int.parse(ruta.split('/')[3]);
      final cuerpo = jsonDecode((request as http.Request).body) as Map;
      final palabra = _palabras.firstWhere((p) => p['id'] == id);
      palabra['oculta'] = cuerpo['oculta'];
      return _json(200, palabra);
    }

    if (metodo == 'PATCH' && ruta.startsWith('/admin/palabras/')) {
      final id = int.parse(ruta.split('/')[3]);
      final cuerpo = jsonDecode((request as http.Request).body) as Map;
      final palabra = _palabras.firstWhere((p) => p['id'] == id);
      palabra['texto'] = cuerpo['texto'];
      palabra['id_nivel'] = cuerpo['id_nivel'];
      palabra['significado_es'] = cuerpo['significado_es'];
      palabra['oracion_ejemplo'] = cuerpo['oracion_ejemplo'];
      return _json(200, palabra);
    }

    if (metodo == 'POST' && ruta.endsWith('/audio')) {
      final id = int.parse(ruta.split('/')[3]);
      final palabra = _palabras.firstWhere((p) => p['id'] == id);
      final multipart = request as http.MultipartRequest;
      final nombre = multipart.files.single.filename ?? 'audio.mp3';
      final extension = nombre.substring(nombre.lastIndexOf('.'));
      palabra['url_audio'] = '/assets/audios/$id$extension';
      return _json(200, palabra);
    }

    throw StateError('Ruta no simulada en la prueba: $metodo $ruta');
  }

  // charset=utf-8 explícito: sin esto, http.Response decodifica el cuerpo
  // como latin1 por default y cualquier acento ("Fácil", "más") sale mal
  // formado — así responde siempre el backend real (Express), pero hay que
  // repetirlo a mano aquí porque este es un cuerpo fabricado en la prueba.
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

/// Cliente que hace fallar la primera petición a /admin/palabras (simulando
/// una falla de red real, no un 4xx del backend), y luego funciona normal —
/// para probar el botón "Reintentar" de cargarInicial().
class _ClienteConFalloInicial extends http.BaseClient {
  _ClienteConFalloInicial(this._backend);

  final _BackendSimulado _backend;
  bool _yaFallo = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/admin/palabras' && !_yaFallo) {
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

/// RF-38 (T-065): hace fallar la PRIMERA petición POST /admin/palabras con
/// un 500 (no una falla de red) y deja pasar todo lo demás normal — para
/// probar que "Reintentar" en el banner reenvía el MISMO texto capturado en
/// el diálogo, sin tener que volver a abrirlo.
class _ClienteConFalloEnCrear extends http.BaseClient {
  _ClienteConFalloEnCrear(this._backend);

  final _BackendSimulado _backend;
  bool _yaFallo = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' &&
        request.url.path == '/admin/palabras' &&
        !_yaFallo) {
      _yaFallo = true;
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

/// RF-38 (T-065): mientras [fallarSegundaPagina] sea true, toda petición de
/// la página 2 responde 500 (la carga incremental por scroll infinito) —
/// la página 1 y todo lo demás funcionan normal. Es un interruptor y no
/// "falla una sola vez" porque el listener del scroll puede volver a
/// disparar la carga varias veces seguidas mientras la prueba arrastra la
/// lista hasta el final.
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

/// Cliente que hace que POST .../audio responda como el backend real
/// (T-025) cuando rechaza un archivo — mismo contrato {error:{code,message}}
/// y 400 — para probar que la pantalla muestra ese mensaje en vez de
/// tronar. El resto de las rutas se comportan normal.
class _ClienteConAudioRechazado extends http.BaseClient {
  _ClienteConAudioRechazado(this._backend);

  final _BackendSimulado _backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/audio')) {
      final cuerpo = jsonEncode({
        'error': {
          'code': 'AUDIO_TAMANO_INVALIDO',
          'message': 'El archivo no puede pesar más de 1 MB.',
        },
      });
      return http.StreamedResponse(
        Stream.value(utf8.encode(cuerpo)),
        400,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final respuesta = _backend.responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(respuesta.body)),
      respuesta.statusCode,
      headers: respuesta.headers,
    );
  }
}

// FilePicker.platform es "late" y esta suite nunca lo inicializa por su
// cuenta (no hay canal de plataforma real bajo flutter test), así que ni
// siquiera se puede LEER un "valor anterior" para restaurarlo después: la
// sola lectura truena con LateInitializationError. Cada prueba que lo usa
// simplemente lo asigna, sin intentar guardar/restaurar nada.
class _FilePickerDePrueba extends FilePicker {
  _FilePickerDePrueba(this._resultado);

  final FilePickerResult? _resultado;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('no usado en la prueba') bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => _resultado;
}

// T-071: misma localización que la app real (core/localizacion.dart), para que
// los textos que pone el propio Flutter también salgan en español aquí.
Widget _envolver(Widget child) => MaterialApp(
  locale: localeDeLaInterfaz,
  supportedLocales: localesSoportados,
  localizationsDelegates: delegadosDeLocalizacion,
  home: child,
  debugShowCheckedModeBanner: false,
);

void main() {
  testWidgets(
    'con sesión de alumno, muestra el aviso de "solo profesores" y no carga nada',
    (tester) async {
      final cliente = _ClienteHttpDePrueba(_BackendSimulado());
      final auth = await _authConSesion('alumno', cliente);

      await tester.pumpWidget(
        _envolver(AdminCatalogoScreen(authController: auth)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Esta pantalla es exclusiva para profesores.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      // T-071 (RNF-01): ningún texto visible ni anunciado en inglés.
      await expectSoloEspanol(tester, pantalla: 'catálogo (aviso solo profesores)');
    },
  );

  testWidgets(
    'con sesión de profesor, lista las palabras con sus chips de estado',
    (tester) async {
      final backend = _BackendSimulado(
        palabrasIniciales: [
          {
            'id': 1,
            'texto': 'business',
            'id_nivel': 1,
            'significado_es': 'negocio',
            'oracion_ejemplo': 'This is a business.',
            'url_audio': '/assets/audios/1.mp3',
            'completa': true,
            'oculta': false,
          },
          {
            'id': 2,
            'texto': 'payment',
            'id_nivel': 1,
            'significado_es': null,
            'oracion_ejemplo': null,
            'url_audio': null,
            'completa': false,
            'oculta': true,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('business'), findsOneWidget);
      expect(find.text('payment'), findsOneWidget);
      expect(find.text('Completa'), findsOneWidget);
      expect(find.text('Incompleta'), findsOneWidget);
      expect(find.text('Visible'), findsOneWidget);
      expect(find.text('Oculta'), findsOneWidget);
      // T-071 (RNF-01): lo único en inglés son las palabras del catálogo.
      await expectSoloEspanol(
        tester,
        contenidoIngles: ['business', 'payment', 'This is a business.'],
        pantalla: 'catálogo con palabras',
      );
    },
  );

  testWidgets(
    'si falla la carga inicial, muestra el error y permite reintentar',
    (tester) async {
      final backend = _BackendSimulado();
      final cliente = _ClienteConFalloInicial(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
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
      await expectSoloEspanol(tester, pantalla: 'catálogo con error de carga');

      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Todavía no hay palabras en el catálogo.'),
        findsOneWidget,
      );
      await expectSoloEspanol(tester, pantalla: 'catálogo vacío');
    },
  );

  testWidgets('agregar palabra: exige texto, y al guardar aparece en la lista', (
    tester,
  ) async {
    final backend = _BackendSimulado();
    final cliente = _ClienteHttpDePrueba(backend);
    final auth = await _authConSesion('profesor', cliente);

    await tester.pumpWidget(
      _envolver(
        AdminCatalogoScreen(
          authController: auth,
          controller: _controladorDePrueba(auth, cliente),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Guardar sin texto: debe rechazarse sin llamar a la API.
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pump();
    expect(find.text('El texto es obligatorio.'), findsOneWidget);
    // T-071 (RNF-01): el diálogo de alta, con su error de validación.
    await expectSoloEspanol(tester, pantalla: 'diálogo Agregar palabra con error');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Texto (en inglés)'),
      'notebook',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('notebook'), findsOneWidget);
    expect(find.text('Incompleta'), findsOneWidget);
  });

  testWidgets(
    'RF-38 (T-065): si crear() falla por un 5xx, el banner de reintentar reenvía el MISMO texto sin reabrir el diálogo',
    (tester) async {
      final backend = _BackendSimulado();
      final cliente = _ClienteConFalloEnCrear(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Texto (en inglés)'),
        'notebook',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // El diálogo YA se cerró (Guardar lo hace antes de llamar a crear(),
      // ver _DialogoPalabra) — el primer intento de red falló con 500.
      expect(find.text('Agregar palabra'), findsNothing);
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(
        find.text('notebook'),
        findsNothing,
        reason: 'todavía no se guardó — el primer intento falló',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsNothing);
      expect(
        find.text('notebook'),
        findsOneWidget,
        reason: 'Reintentar mandó el MISMO texto ya capturado, sin volver a abrir el diálogo',
      );
    },
  );

  testWidgets(
    'editar palabra: el diálogo llega prellenado y guarda los cambios',
    (tester) async {
      final backend = _BackendSimulado(
        palabrasIniciales: [
          {
            'id': 5,
            'texto': 'original',
            'id_nivel': 1,
            'significado_es': 'significado',
            'oracion_ejemplo': 'An example.',
            'url_audio': null,
            'completa': false,
            'oculta': false,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('original'));
      await tester.pumpAndSettle();

      expect(find.text('Editar palabra'), findsOneWidget);
      final campoTexto = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Texto (en inglés)'),
      );
      // Prellenado: el campo ya trae "original" como texto actual.
      expect(campoTexto.controller!.text, 'original');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Texto (en inglés)'),
        'editado',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('editado'), findsOneWidget);
      expect(find.text('original'), findsNothing);
    },
  );

  testWidgets('ocultar/mostrar: el botón de visibilidad alterna el estado', (
    tester,
  ) async {
    final backend = _BackendSimulado(
      palabrasIniciales: [
        {
          'id': 7,
          'texto': 'visible-al-inicio',
          'id_nivel': 1,
          'significado_es': null,
          'oracion_ejemplo': null,
          'url_audio': null,
          'completa': false,
          'oculta': false,
        },
      ],
    );
    final cliente = _ClienteHttpDePrueba(backend);
    final auth = await _authConSesion('profesor', cliente);

    await tester.pumpWidget(
      _envolver(
        AdminCatalogoScreen(
          authController: auth,
          controller: _controladorDePrueba(auth, cliente),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visible'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    expect(find.text('Oculta'), findsOneWidget);
    expect(find.text('Visible'), findsNothing);
  });

  testWidgets('subir audio: usa el archivo elegido y actualiza url_audio', (
    tester,
  ) async {
    final backend = _BackendSimulado(
      palabrasIniciales: [
        {
          'id': 9,
          'texto': 'con-audio-nuevo',
          'id_nivel': 1,
          'significado_es': null,
          'oracion_ejemplo': null,
          'url_audio': null,
          'completa': false,
          'oculta': false,
        },
      ],
    );
    final cliente = _ClienteHttpDePrueba(backend);
    final auth = await _authConSesion('profesor', cliente);

    FilePicker.platform = _FilePickerDePrueba(
      FilePickerResult([
        PlatformFile(
          name: 'grabacion.mp3',
          size: 1000,
          bytes: Uint8List.fromList(List.filled(1000, 1)),
        ),
      ]),
    );

    await tester.pumpWidget(
      _envolver(
        AdminCatalogoScreen(
          authController: auth,
          controller: _controladorDePrueba(auth, cliente),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.audiotrack));
    await tester.pumpAndSettle();

    expect(find.text('Audio actualizado.'), findsOneWidget);
  });

  testWidgets(
    'subir audio: si se cancela el selector, no truena ni llama a la API',
    (tester) async {
      final backend = _BackendSimulado(
        palabrasIniciales: [
          {
            'id': 11,
            'texto': 'sin-cambios',
            'id_nivel': 1,
            'significado_es': null,
            'oracion_ejemplo': null,
            'url_audio': null,
            'completa': false,
            'oculta': false,
          },
        ],
      );
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      FilePicker.platform = _FilePickerDePrueba(null);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();

      expect(find.text('Audio actualizado.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subir audio: si el backend lo rechaza (formato/tamaño), muestra el error sin tronar',
    (tester) async {
      final backend = _BackendSimulado(
        palabrasIniciales: [
          {
            'id': 13,
            'texto': 'audio-invalido',
            'id_nivel': 1,
            'significado_es': null,
            'oracion_ejemplo': null,
            'url_audio': null,
            'completa': false,
            'oculta': false,
          },
        ],
      );
      final cliente = _ClienteConAudioRechazado(backend);
      final auth = await _authConSesion('profesor', cliente);

      FilePicker.platform = _FilePickerDePrueba(
        FilePickerResult([
          PlatformFile(
            name: 'demasiado-grande.mp3',
            size: 2 * 1024 * 1024,
            bytes: Uint8List.fromList(List.filled(2 * 1024 * 1024, 1)),
          ),
        ]),
      );

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();

      expect(
        find.text('El archivo no puede pesar más de 1 MB.'),
        findsOneWidget,
      );
      expect(find.text('Audio actualizado.'), findsNothing);
      expect(tester.takeException(), isNull);
      // La palabra sigue igual: el rechazo no debe dejarla a medio actualizar.
      expect(find.text('audio-invalido'), findsOneWidget);
      expect(find.text('Incompleta'), findsOneWidget);
    },
  );

  testWidgets(
    'paginación: hacer scroll cerca del final carga la siguiente página automáticamente',
    (tester) async {
      final palabras = List.generate(
        25,
        (i) => {
          'id': i + 1,
          'texto': 'palabra-$i',
          'id_nivel': 1,
          'significado_es': null,
          'oracion_ejemplo': null,
          'url_audio': null,
          'completa': false,
          'oculta': false,
        },
      );
      final backend = _BackendSimulado(palabrasIniciales: palabras);
      final cliente = _ClienteHttpDePrueba(backend);
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('palabra-0'), findsOneWidget);
      expect(find.text('palabra-20'), findsNothing);

      // RNF-12: scroll infinito, sin botón — arrastrar la lista hasta cerca
      // del final debe disparar cargarMas() sola (_alLlegarAlFinal).
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
    'RF-38 (T-065): si la carga incremental falla por un 5xx, avisa con el banner (antes fallaba en silencio) sin perder la lista ya cargada, y Reintentar carga la página faltante',
    (tester) async {
      final palabras = List.generate(
        25,
        (i) => {
          'id': i + 1,
          'texto': 'palabra-$i',
          'id_nivel': 1,
          'significado_es': null,
          'oracion_ejemplo': null,
          'url_audio': null,
          'completa': false,
          'oculta': false,
        },
      );
      final cliente = _ClienteQueFallaLaSegundaPagina(
        _BackendSimulado(palabrasIniciales: palabras),
      );
      final auth = await _authConSesion('profesor', cliente);

      await tester.pumpWidget(
        _envolver(
          AdminCatalogoScreen(
            authController: auth,
            controller: _controladorDePrueba(auth, cliente),
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
      expect(
        find.text('palabra-0'),
        findsNothing,
        reason: 'ya se hizo scroll hacia abajo — el primer elemento salió de la vista, no de la lista',
      );
      expect(tester.takeException(), isNull);

      // El backend "se recupera": Reintentar debe traer la página 2.
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
        reason: 'la página 2 (palabras 20 a 24) llegó tras Reintentar',
      );
    },
  );
}

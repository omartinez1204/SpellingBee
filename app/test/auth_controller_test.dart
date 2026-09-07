import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/auth_controller.dart';

// Sin plugin real: sobreescribe justo lo que AuthController usa, para poder
// probar la persistencia de sesión sin flutter_secure_storage (no disponible
// en un test que no corre en un dispositivo).
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

String _jwtDePrueba({required bool debeCambiarContrasena}) {
  String segmento(Map<String, Object?> mapa) =>
      base64Url.encode(utf8.encode(jsonEncode(mapa))).replaceAll('=', '');

  final header = segmento({'alg': 'HS256', 'typ': 'JWT'});
  final payload = segmento({
    'sub': 42,
    'rol': 'profesor',
    'debe_cambiar_contrasena': debeCambiarContrasena,
    'exp':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
  });
  return '$header.$payload.firma-no-verificada-en-el-cliente';
}

void main() {
  // Bug real encontrado verificando T-016 en un emulador: tras cambiar la
  // contraseña, el JWT guardado sigue trayendo debe_cambiar_contrasena=true
  // (es inmutable), así que sin este mecanismo la app forzaba el cambio de
  // nuevo en cada arranque, en un loop, aunque el backend ya diga false.
  test(
    'tras un cambio de contraseña exitoso, un reinicio de la app no vuelve a forzar el cambio',
    () async {
      final storage = _AlmacenDePruebaEnMemoria();
      final token = _jwtDePrueba(debeCambiarContrasena: true);
      await storage.write(key: 'jwt_token', value: token);
      await storage.write(
        key: 'debe_cambiar_contrasena_resuelto',
        value: 'true',
      );

      final auth = AuthController(storage: storage);
      await auth.cargarSesionGuardada();

      expect(auth.sesion, isNotNull);
      expect(auth.sesion!.debeCambiarContrasena, isFalse);
    },
  );

  test(
    'sin la resolución local, un token con debe_cambiar_contrasena=true lo respeta',
    () async {
      final storage = _AlmacenDePruebaEnMemoria();
      await storage.write(
        key: 'jwt_token',
        value: _jwtDePrueba(debeCambiarContrasena: true),
      );

      final auth = AuthController(storage: storage);
      await auth.cargarSesionGuardada();

      expect(auth.sesion!.debeCambiarContrasena, isTrue);
    },
  );

  test('cerrar sesión limpia también la resolución local guardada', () async {
    final storage = _AlmacenDePruebaEnMemoria();
    await storage.write(
      key: 'jwt_token',
      value: _jwtDePrueba(debeCambiarContrasena: true),
    );
    await storage.write(key: 'debe_cambiar_contrasena_resuelto', value: 'true');

    final auth = AuthController(storage: storage);
    await auth.cargarSesionGuardada();
    await auth.cerrarSesion();

    expect(await storage.read(key: 'debe_cambiar_contrasena_resuelto'), isNull);
    expect(await storage.read(key: 'jwt_token'), isNull);
  });
}

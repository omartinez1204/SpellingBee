import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'jwt.dart';
import 'sesion_usuario.dart';

const _claveToken = 'jwt_token';
// El JWT es inmutable: si se cambia la contraseña a mitad de sesión, el
// debe_cambiar_contrasena original sigue "true" dentro del propio token (no
// hay endpoint para pedir uno nuevo sin volver a loguearse). Este flag local
// registra que, para esta sesión, ya se resolvió, y gana sobre lo que diga el
// token guardado la próxima vez que arranque la app.
const _claveDebeCambiarResuelto = 'debe_cambiar_contrasena_resuelto';

/// Estado de sesión de toda la app + llamadas a los endpoints de T-010 a
/// T-014. Un solo ChangeNotifier alcanza para el alcance de T-016: no hay
/// necesidad de un paquete de manejo de estado todavía.
class AuthController extends ChangeNotifier {
  AuthController({ApiClient? apiClient, FlutterSecureStorage? storage})
    : _api = apiClient ?? ApiClient(),
      _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  SesionUsuario? _sesion;
  SesionUsuario? get sesion => _sesion;
  bool get estaAutenticado => _sesion != null;

  /// Se llama una vez al arrancar la app, antes de runApp.
  Future<void> cargarSesionGuardada() async {
    final token = await _storage.read(key: _claveToken);
    if (token == null) return;

    try {
      final payload = decodificarPayloadJwt(token);
      if (tokenExpirado(payload)) {
        await _storage.delete(key: _claveToken);
        return;
      }
      var sesion = SesionUsuario.desdeToken(token);
      if (sesion.debeCambiarContrasena) {
        final resuelto = await _storage.read(key: _claveDebeCambiarResuelto);
        if (resuelto == 'true') {
          sesion = sesion.conDebeCambiarContrasena(false);
        }
      }
      _sesion = sesion;
    } catch (_) {
      // Token corrupto o con forma inesperada: no dejar a la persona en un
      // estado de "sesión" que va a fallar en la primera llamada real.
      await _storage.delete(key: _claveToken);
    }
  }

  // RF-01, RF-37 (T-010). No inicia sesión sola: el backend no emite JWT en
  // el registro, hay que loguearse después.
  Future<void> registrar({
    required String matricula,
    required String nombre,
    required String apellidoPaterno,
    required String apellidoMaterno,
    required String carrera,
    required int semestre,
    required String correo,
    required String contrasena,
  }) {
    return _api.post('/auth/registro', {
      'matricula': matricula,
      'nombre': nombre,
      'apellido_paterno': apellidoPaterno,
      'apellido_materno': apellidoMaterno,
      'carrera': carrera,
      'semestre': semestre,
      'correo': correo,
      'contrasena': contrasena,
      'acepto_aviso_privacidad': true,
    });
  }

  // RF-01 (alumno) / RF-02 (profesor) (T-011).
  Future<void> iniciarSesion({
    required String nombreUsuario,
    required String contrasena,
  }) async {
    final respuesta = await _api.post('/auth/login', {
      'nombre_usuario': nombreUsuario,
      'contrasena': contrasena,
    });
    final token = respuesta['access_token'] as String;
    await _storage.write(key: _claveToken, value: token);
    // Un login nuevo trae la verdad fresca del backend en el propio token;
    // cualquier resolución local de una sesión anterior ya no aplica.
    await _storage.delete(key: _claveDebeCambiarResuelto);
    _sesion = SesionUsuario.desdeToken(token);
    notifyListeners();
  }

  // RF-04 (T-012). Stateless: si la llamada falla (sin conexión, etc.) igual
  // se cierra la sesión localmente — no tiene sentido dejar a alguien
  // atrapado "logueado" solo porque no hubo internet para avisarle al backend.
  Future<void> cerrarSesion() async {
    try {
      await _api.post('/auth/logout', {}, token: _sesion?.token);
    } catch (_) {
      // intencional: ver comentario arriba.
    }
    await _storage.delete(key: _claveToken);
    await _storage.delete(key: _claveDebeCambiarResuelto);
    _sesion = null;
    notifyListeners();
  }

  // RF-03, paso 1 (T-013).
  Future<void> recuperarPassword(String nombreUsuario) {
    return _api.post('/auth/recuperar-password', {
      'nombre_usuario': nombreUsuario,
    });
  }

  // RF-03, paso 2 (T-013): token recibido "por correo" (en dev, log del backend).
  Future<void> restablecerPassword({
    required String token,
    required String contrasenaNueva,
  }) {
    return _api.post('/auth/restablecer-password', {
      'token': token,
      'contrasena_nueva': contrasenaNueva,
    });
  }

  // RF-35, RF-36 (T-014). Requiere sesión.
  Future<void> cambiarPassword({
    required String contrasenaActual,
    required String contrasenaNueva,
  }) async {
    final sesionActual = _sesion;
    if (sesionActual == null) {
      throw StateError('cambiarPassword llamado sin sesión iniciada.');
    }

    await _api.patch('/auth/cambiar-password', {
      'contrasena_actual': contrasenaActual,
      'contrasena_nueva': contrasenaNueva,
    }, token: sesionActual.token);

    // RF-36: el propio cambio exitoso ya cumplió la obligación; refleja lo
    // que el backend acaba de hacer sin esperar a un nuevo login. El flag se
    // persiste porque el JWT guardado no se puede "editar" para quitarle el
    // debe_cambiar_contrasena original (ver nota junto a la constante).
    await _storage.write(key: _claveDebeCambiarResuelto, value: 'true');
    _sesion = sesionActual.conDebeCambiarContrasena(false);
    notifyListeners();
  }
}

import 'jwt.dart';

/// Payload del JWT emitido por POST /auth/login (backend/src/auth/auth.service.ts).
class SesionUsuario {
  const SesionUsuario({
    required this.token,
    required this.sub,
    required this.rol,
    required this.debeCambiarContrasena,
  });

  factory SesionUsuario.desdeToken(String token) {
    final payload = decodificarPayloadJwt(token);
    return SesionUsuario(
      token: token,
      sub: payload['sub'] as int,
      rol: payload['rol'] as String,
      debeCambiarContrasena: payload['debe_cambiar_contrasena'] as bool,
    );
  }

  final String token;
  final int sub;
  final String rol;
  final bool debeCambiarContrasena;

  bool get esProfesor => rol == 'profesor';

  SesionUsuario conDebeCambiarContrasena(bool valor) => SesionUsuario(
    token: token,
    sub: sub,
    rol: rol,
    debeCambiarContrasena: valor,
  );
}

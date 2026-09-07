import 'dart:convert';

/// Decodifica el payload de un JWT (sin verificar la firma: el backend ya la
/// verifica en cada llamada protegida; esto es solo para que la app sepa
/// rol/debe_cambiar_contrasena sin pedirlos aparte — no hay GET /auth/perfil).
Map<String, dynamic> decodificarPayloadJwt(String token) {
  final partes = token.split('.');
  if (partes.length != 3) {
    throw const FormatException('El token no tiene el formato de un JWT.');
  }
  final normalizado = base64Url.normalize(partes[1]);
  final payload = utf8.decode(base64Url.decode(normalizado));
  return jsonDecode(payload) as Map<String, dynamic>;
}

bool tokenExpirado(Map<String, dynamic> payload) {
  final exp = payload['exp'];
  if (exp is! int) return true;
  final expiracion = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  return DateTime.now().isAfter(expiracion);
}

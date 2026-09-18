/// Error de la API, con la misma forma que backend/src/common/filters/http-exception.filter.ts:
/// { "error": { "code", "message" } }.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;

  /// Status HTTP real de la respuesta, o null si nunca hubo respuesta (sin
  /// conexión, tiempo de espera agotado, servidor inalcanzable — ver
  /// ApiClient._enviar()). Es la base de [esBackendNoDisponible]: no depende
  /// de adivinar qué `code` de negocio manda el backend en cada caso, así
  /// que sigue funcionando aunque el backend agregue códigos nuevos.
  final int? statusCode;

  /// RF-38 (T-065): "falla por falta de conectividad o por no poder
  /// alcanzar el servidor" (statusCode null, sin respuesta) "o" un 5xx (el
  /// servidor SÍ respondió, pero con un error de su lado, no del alumno) —
  /// ambos casos son "el backend no está disponible" desde la perspectiva
  /// de quien usa la app, y ambos deben mostrar el mismo mensaje + botón de
  /// reintentar sin perder el formulario en curso. Un 4xx (validación,
  /// credenciales, permisos) NO cuenta: ese es un error sobre lo que la
  /// persona hizo, con su propio mensaje específico — "reintentar" la misma
  /// operación sin cambiar nada no serviría de nada ahí.
  bool get esBackendNoDisponible => statusCode == null || statusCode! >= 500;

  @override
  String toString() => message;
}

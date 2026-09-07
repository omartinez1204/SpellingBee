/// Error de la API, con la misma forma que backend/src/common/filters/http-exception.filter.ts:
/// { "error": { "code", "message" } }.
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// URL base del backend. El emulador de Android no puede usar "localhost"
/// para llegar a la máquina host — 10.0.2.2 es el alias especial que sí
/// llega. Para un dispositivo físico o Windows/Chrome, sobreescribir con:
///   `flutter run --dart-define=API_BASE_URL=http://<ip-de-tu-maquina>:3000`
const String _baseUrlPorDefecto = 'http://10.0.2.2:3000';

/// Cliente HTTP delgado hacia el backend NestJS. Sin prefijo /api/v1: el
/// backend real todavía no lo tiene (ver docs/diseno-tecnico.md §3, decisión
/// pendiente señalada al implementar T-010).
class ApiClient {
  ApiClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      baseUrl = const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: _baseUrlPorDefecto,
      );

  final http.Client _http;
  final String baseUrl;

  Future<Map<String, dynamic>> get(String path, {String? token}) {
    return _enviar(() => _http.get(_uri(path), headers: _headers(token)));
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _enviar(
      () => _http.post(
        _uri(path),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _enviar(
      () => _http.patch(
        _uri(path),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> _enviar(
    Future<http.Response> Function() hacer,
  ) async {
    http.Response respuesta;
    try {
      respuesta = await hacer().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ApiException(
        'SIN_CONEXION',
        'El servidor tardó demasiado en responder. Intenta de nuevo.',
      );
    } catch (_) {
      throw const ApiException(
        'SIN_CONEXION',
        'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
      );
    }

    final Map<String, dynamic> cuerpo;
    try {
      cuerpo = respuesta.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(respuesta.body) as Map<String, dynamic>;
    } on FormatException {
      throw const ApiException(
        'RESPUESTA_INVALIDA',
        'El servidor respondió algo inesperado.',
      );
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return cuerpo;
    }

    final error = cuerpo['error'] as Map<String, dynamic>?;
    throw ApiException(
      (error?['code'] as String?) ?? 'ERROR',
      (error?['message'] as String?) ?? 'Ocurrió un error inesperado.',
    );
  }
}

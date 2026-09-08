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

  Future<Map<String, dynamic>> get(String path, {String? token}) async {
    final cuerpo = await _enviar(
      () => _http.get(_uri(path), headers: _headers(token)),
    );
    return cuerpo as Map<String, dynamic>;
  }

  /// Igual que get(), pero para endpoints cuya raíz JSON es un arreglo
  /// (p. ej. GET /niveles: "[{...}, {...}]", no "{"niveles": [...]}") — un
  /// solo "get()" que siempre castea a Map no sirve para esa forma.
  Future<List<dynamic>> getLista(String path, {String? token}) async {
    final cuerpo = await _enviar(
      () => _http.get(_uri(path), headers: _headers(token)),
    );
    return cuerpo as List<dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final cuerpo = await _enviar(
      () => _http.post(
        _uri(path),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    return cuerpo as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final cuerpo = await _enviar(
      () => _http.patch(
        _uri(path),
        headers: _headers(token),
        body: jsonEncode(body),
      ),
    );
    return cuerpo as Map<String, dynamic>;
  }

  /// Subida multipart (T-025: POST /admin/palabras/:id/audio). Sin
  /// Content-Type manual: MultipartRequest arma el suyo propio con el
  /// boundary correcto — ponerlo a mano rompería el parseo del backend.
  Future<Map<String, dynamic>> subirArchivo(
    String path,
    String campoFormulario,
    List<int> bytes,
    String nombreArchivo, {
    String? token,
  }) async {
    final cuerpo = await _enviar(() async {
      final solicitud = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headersAuth(token))
        ..files.add(
          http.MultipartFile.fromBytes(
            campoFormulario,
            bytes,
            filename: nombreArchivo,
          ),
        );
      final respuestaEnFlujo = await _http.send(solicitud);
      return http.Response.fromStream(respuestaEnFlujo);
    });
    return cuerpo as Map<String, dynamic>;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    ..._headersAuth(token),
  };

  Map<String, String> _headersAuth(String? token) => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Decodifica la respuesta y resuelve al cuerpo ya listo para usarse: el
  /// tipo real (Map para la mayoría de endpoints, List para los que
  /// regresan un arreglo en la raíz) lo decide quien llama, vía el cast en
  /// get()/getLista()/post()/etc. — este método solo sabe manejar red y el
  /// contrato uniforme de error, no la forma de cada endpoint.
  Future<dynamic> _enviar(Future<http.Response> Function() hacer) async {
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

    final dynamic cuerpo;
    try {
      cuerpo = respuesta.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(respuesta.body);
    } on FormatException {
      throw const ApiException(
        'RESPUESTA_INVALIDA',
        'El servidor respondió algo inesperado.',
      );
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return cuerpo;
    }

    // Los errores siempre son { "error": { "code", "message" } } (un mapa),
    // sin importar si el endpoint exitoso regresa un mapa o una lista.
    final mapaError = cuerpo is Map<String, dynamic> ? cuerpo : null;
    final error = mapaError?['error'] as Map<String, dynamic>?;
    throw ApiException(
      (error?['code'] as String?) ?? 'ERROR',
      (error?['message'] as String?) ?? 'Ocurrió un error inesperado.',
    );
  }
}

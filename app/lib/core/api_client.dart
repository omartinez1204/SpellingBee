import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'monitor_conectividad.dart';
import 'monitor_conectividad_connectivity_plus.dart';

/// URL base del backend. El emulador de Android no puede usar "localhost"
/// para llegar a la máquina host — 10.0.2.2 es el alias especial que sí
/// llega. Para un dispositivo físico o Windows/Chrome, sobreescribir con:
///   `flutter run --dart-define=API_BASE_URL=http://<ip-de-tu-maquina>:3000`
const String _baseUrlPorDefecto = 'http://10.0.2.2:3000';

/// Cliente HTTP delgado hacia el backend NestJS. Sin prefijo /api/v1: el
/// backend real todavía no lo tiene (ver docs/diseno-tecnico.md §3, decisión
/// pendiente señalada al implementar T-010).
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    MonitorConectividad? monitorConectividad,
  }) : _http = httpClient ?? http.Client(),
       // No initializing formal: el parámetro debe seguir siendo público
       // (monitorConectividad:) para quien construye ApiClient desde otros
       // archivos — mismo motivo que en SincronizadorPractica.
       // ignore: prefer_initializing_formals
       _monitorConectividad = monitorConectividad,
       baseUrl = const String.fromEnvironment(
         'API_BASE_URL',
         defaultValue: _baseUrlPorDefecto,
       );

  final http.Client _http;

  /// RF-38 (T-065): solo se consulta cuando una llamada falla SIN respuesta
  /// (ver [_mensajeDeFallaDeTransporte]) — nunca en el camino feliz. null
  /// (el caso de casi todos los servicios, que arman `ApiClient()` sin
  /// argumentos) usa el monitor real, creado en ese momento.
  final MonitorConectividad? _monitorConectividad;
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

  /// RF-38 (T-065): "no tienes conexión" y "el servidor no responde" son
  /// problemas distintos con soluciones distintas (conectarse vs. esperar), y
  /// el indicador de conexión de T-064 ya le dice a la persona cuál de los
  /// dos es el suyo — un mensaje que dijera "verifica tu conexión" con el
  /// indicador en verde se contradice. Como ambos llegan aquí como la MISMA
  /// falla de transporte (sin respuesta), se decide por el estado real del
  /// dispositivo (MonitorConectividad, la misma señal de T-064): sin red →
  /// hay que conectarse; con red → el que no responde es el servidor.
  ///
  /// El `code` sigue siendo SIN_CONEXION en ambos casos a propósito: la cola
  /// de práctica offline (RF-33, T-062) se activa igual en los dos — un
  /// intento que no pudo llegar al servidor se guarda sin importar por qué.
  ///
  /// Si el estado no se puede consultar (sin plataforma, error, o tarda más
  /// de un segundo) se cae al mensaje neutro de siempre: un mensaje menos
  /// preciso es mejor que una falla al reportar una falla.
  Future<String> _mensajeDeFallaDeTransporte({
    required bool esTiempoAgotado,
  }) async {
    EstadoConexion? estado;
    try {
      estado = await (_monitorConectividad ?? MonitorConectividadReal())
          .obtenerActual()
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      estado = null;
    }

    switch (estado) {
      case EstadoConexion.sinConexion:
        return 'No tienes conexión a internet. Conéctate e inténtalo de nuevo.';
      case EstadoConexion.enLinea:
        return esTiempoAgotado
            ? 'El servidor tardó demasiado en responder. Inténtalo de nuevo en unos minutos.'
            : 'El servidor no responde en este momento. Inténtalo de nuevo en unos minutos.';
      case null:
        return esTiempoAgotado
            ? 'El servidor tardó demasiado en responder. Intenta de nuevo.'
            : 'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.';
    }
  }

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
      throw ApiException(
        'SIN_CONEXION',
        await _mensajeDeFallaDeTransporte(esTiempoAgotado: true),
      );
    } catch (_) {
      throw ApiException(
        'SIN_CONEXION',
        await _mensajeDeFallaDeTransporte(esTiempoAgotado: false),
      );
    }

    final dynamic cuerpo;
    try {
      cuerpo = respuesta.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(respuesta.body);
    } on FormatException {
      // RF-38 (T-065): SÍ hubo respuesta (statusCode real, ver más abajo) —
      // un 5xx con un cuerpo que ni siquiera es JSON (p. ej. la página de
      // error de un balanceador delante del backend) debe seguir contando
      // como "backend no disponible", no perder esa clasificación solo
      // porque el cuerpo no se pudo decodificar.
      throw ApiException(
        'RESPUESTA_INVALIDA',
        'El servidor respondió algo inesperado.',
        statusCode: respuesta.statusCode,
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
      // RF-38 (T-065): se manda el status real sin importar qué "code" de
      // negocio haya elegido el backend — ApiException.esBackendNoDisponible
      // se apoya en esto (>=500), no en adivinar el string del code.
      statusCode: respuesta.statusCode,
    );
  }
}

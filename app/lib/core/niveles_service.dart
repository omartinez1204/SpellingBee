import 'api_client.dart';
import 'nivel.dart';
import 'paquete_nivel.dart';

/// GET /niveles (T-020) — público, sin sesión. Se usa para llenar el
/// selector de nivel del panel de administración (T-027) y, junto con
/// obtenerDescarga(), para la pantalla de niveles descargables del alumno
/// (T-061).
class NivelesService {
  NivelesService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// T-061: para armar la url completa de cada audio del paquete antes de
  /// precachearlo — mismo motivo que PalabrasService.baseUrl.
  String get baseUrl => _api.baseUrl;

  Future<List<Nivel>> listar() async {
    final json = await _api.getLista('/niveles');
    return json
        .map((item) => Nivel.desdeJson(item as Map<String, dynamic>))
        .toList();
  }

  // RF-31 (T-060/T-061): paquete completo de un nivel (palabras + urls de
  // audio) para descargar y usar sin conexión (RF-32).
  Future<PaqueteNivel> obtenerDescarga(int idNivel) async {
    final json = await _api.get('/niveles/$idNivel/descarga');
    return PaqueteNivel.desdeJson(json);
  }
}

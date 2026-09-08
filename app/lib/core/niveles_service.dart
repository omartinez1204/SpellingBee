import 'api_client.dart';
import 'nivel.dart';

/// GET /niveles (T-020) — público, sin sesión. Se usa aquí solo para llenar
/// el selector de nivel del panel de administración (T-027).
class NivelesService {
  NivelesService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<Nivel>> listar() async {
    final json = await _api.getLista('/niveles');
    return json
        .map((item) => Nivel.desdeJson(item as Map<String, dynamic>))
        .toList();
  }
}

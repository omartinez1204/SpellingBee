import 'api_client.dart';
import 'insignia.dart';

/// RF-24 (T-047): GET /progreso/insignias. Autenticado — igual que
/// PracticaService.obtenerMejorTiempoSegundos, el backend responde sobre el
/// alumno del propio JWT, no hay id que mandar.
class InsigniasService {
  InsigniasService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<Insignia>> obtenerInsignias(String token) async {
    final json = await _api.getLista('/progreso/insignias', token: token);
    return json
        .map((elemento) => Insignia.desdeJson(elemento as Map<String, dynamic>))
        .toList();
  }
}

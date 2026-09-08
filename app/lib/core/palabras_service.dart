import 'api_client.dart';
import 'detalle_palabra.dart';

/// Llamadas al catálogo que no dependen de sesión (T-023: GET /palabras/:id
/// es público). Separado de AuthController porque no tiene nada que ver con
/// autenticación ni con el estado de sesión.
class PalabrasService {
  PalabrasService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<DetallePalabra> obtenerDetalle(int idPalabra) async {
    final json = await _api.get('/palabras/$idPalabra');
    return DetallePalabra.desdeJson(json);
  }
}

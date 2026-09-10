import 'api_client.dart';

/// RF-22 (T-042): GET /practica/mejor-tiempo/:idPalabra. Autenticado — el
/// backend responde sobre EL PROPIO alumno de la sesión (no hay id de
/// alumno que mandar, solo el token), así que a diferencia de
/// PalabrasService.obtenerDetalle() (pública, T-023) este método sí
/// necesita un token.
class PracticaService {
  PracticaService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// null significa "sin intento previo" (primera vez con esta palabra) —
  /// no es un error ni una ausencia de dato distinta de esa.
  Future<int?> obtenerMejorTiempoSegundos(int idPalabra, String token) async {
    final json = await _api.get(
      '/practica/mejor-tiempo/$idPalabra',
      token: token,
    );
    return json['mejor_tiempo_segundos'] as int?;
  }
}

import 'api_client.dart';
import 'detalle_palabra.dart';

/// Llamadas al catálogo que no dependen de sesión (T-023: GET /palabras/:id
/// es público). Separado de AuthController porque no tiene nada que ver con
/// autenticación ni con el estado de sesión.
class PalabrasService {
  PalabrasService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  // url_audio viene relativo del backend (p. ej. "/assets/audios/1.mp3") a
  // propósito — ver el comentario en palabras.service.ts. La pantalla de
  // práctica (T-030) necesita esto para armar la url completa que le pasa
  // al reproductor.
  String get baseUrl => _api.baseUrl;

  Future<DetallePalabra> obtenerDetalle(int idPalabra) async {
    final json = await _api.get('/palabras/$idPalabra');
    return DetallePalabra.desdeJson(json);
  }
}

import 'api_client.dart';
import 'palabra_admin.dart';

/// Los 5 endpoints de administración del catálogo (T-024/T-025). Todos
/// exigen rol profesor en el backend (RolesGuard, RNF-07) — este servicio no
/// repite esa validación, solo manda el token; si el token no es de
/// profesor, el backend responde 403 y eso llega como ApiException normal.
class AdminPalabrasService {
  AdminPalabrasService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<ListaPalabrasAdmin> listar({
    required String token,
    int pagina = 1,
    int limite = 20,
  }) async {
    final json = await _api.get(
      '/admin/palabras?pagina=$pagina&limite=$limite',
      token: token,
    );
    return ListaPalabrasAdmin.desdeJson(json);
  }

  Future<PalabraAdmin> crear({
    required String token,
    required String texto,
    required int idNivel,
    String? significadoEs,
    String? oracionEjemplo,
  }) async {
    final json = await _api.post('/admin/palabras', {
      'texto': texto,
      'id_nivel': idNivel,
      'significado_es': ?significadoEs,
      'oracion_ejemplo': ?oracionEjemplo,
    }, token: token);
    return PalabraAdmin.desdeJson(json);
  }

  Future<PalabraAdmin> editar({
    required String token,
    required int id,
    required String texto,
    required int idNivel,
    required String significadoEs,
    required String oracionEjemplo,
  }) async {
    final json = await _api.patch('/admin/palabras/$id', {
      'texto': texto,
      'id_nivel': idNivel,
      'significado_es': significadoEs,
      'oracion_ejemplo': oracionEjemplo,
    }, token: token);
    return PalabraAdmin.desdeJson(json);
  }

  Future<PalabraAdmin> ocultar({
    required String token,
    required int id,
    required bool oculta,
  }) async {
    final json = await _api.patch('/admin/palabras/$id/ocultar', {
      'oculta': oculta,
    }, token: token);
    return PalabraAdmin.desdeJson(json);
  }

  Future<PalabraAdmin> subirAudio({
    required String token,
    required int id,
    required List<int> bytes,
    required String nombreArchivo,
  }) async {
    final json = await _api.subirArchivo(
      '/admin/palabras/$id/audio',
      'audio',
      bytes,
      nombreArchivo,
      token: token,
    );
    return PalabraAdmin.desdeJson(json);
  }
}

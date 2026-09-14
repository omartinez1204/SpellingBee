import 'alumno_con_avance.dart';
import 'api_client.dart';
import 'intento_practica.dart';

/// GET /admin/alumnos y GET /admin/alumnos/:id (T-050/T-051, RF-28/RF-29),
/// con los filtros combinables de T-052 (RF-30). Ambos exigen rol profesor en
/// el backend (RolesGuard, RNF-07) — este servicio no repite esa validación,
/// solo manda el token; si el token no es de profesor, el backend responde
/// 403 y eso llega como ApiException normal (mismo criterio que
/// AdminPalabrasService).
class AdminAlumnosService {
  AdminAlumnosService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<ListaAlumnos> listar({
    required String token,
    int pagina = 1,
    int limite = 20,
    int? nivel,
    String? carrera,
    int? semestre,
  }) async {
    final ruta = _rutaConFiltros(
      '/admin/alumnos',
      pagina: pagina,
      limite: limite,
      nivel: nivel,
      carrera: carrera,
      semestre: semestre,
    );
    final json = await _api.get(ruta, token: token);
    return ListaAlumnos.desdeJson(json);
  }

  Future<DetalleAlumno> detalle({
    required String token,
    required int idAlumno,
    int pagina = 1,
    int limite = 20,
    int? nivel,
    String? carrera,
    int? semestre,
  }) async {
    final ruta = _rutaConFiltros(
      '/admin/alumnos/$idAlumno',
      pagina: pagina,
      limite: limite,
      nivel: nivel,
      carrera: carrera,
      semestre: semestre,
    );
    final json = await _api.get(ruta, token: token);
    return DetalleAlumno.desdeJson(json);
  }

  // Uri(...).toString() arma y escapa la query string por nosotros — carrera
  // trae espacios y acentos ("Ingeniería en Desarrollo de Software") que no
  // se pueden concatenar a mano de forma segura.
  String _rutaConFiltros(
    String path, {
    required int pagina,
    required int limite,
    int? nivel,
    String? carrera,
    int? semestre,
  }) {
    return Uri(
      path: path,
      queryParameters: {
        'pagina': '$pagina',
        'limite': '$limite',
        'nivel': ?nivel?.toString(),
        'carrera': ?carrera,
        'semestre': ?semestre?.toString(),
      },
    ).toString();
  }
}

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

  /// RF-21/RF-27 (T-045): POST /practica. Exactamente estos 4 campos, nunca
  /// audio del alumno (RF-27/RF-40) — el backend además rechaza la petición
  /// entera si trae cualquier campo fuera de estos.
  Future<void> guardarPractica({
    required int idPalabra,
    required int tiempoSegundos,
    required String oracionAlumno,
    required bool deletreoCorrecto,
    required String token,
  }) {
    return _api.post(
      '/practica',
      {
        'id_palabra': idPalabra,
        'tiempo_segundos': tiempoSegundos,
        'oracion_alumno': oracionAlumno,
        'deletreo_correcto': deletreoCorrecto,
      },
      token: token,
    );
  }
}

import 'api_client.dart';
import 'fecha_local.dart';
import 'insignia.dart';
import 'registro_practica_pendiente.dart';

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

  /// RF-21/RF-23/RF-27 (T-045/T-046): POST /practica. Exactamente estos 5
  /// campos, nunca audio del alumno (RF-27/RF-40) — el backend además
  /// rechaza la petición entera si trae cualquier campo fuera de estos.
  ///
  /// `fechaLocal` es la fecha CALENDARIO LOCAL DEL DISPOSITIVO (RF-23), no
  /// un instante — por eso se recibe ya como el DateTime completo (para no
  /// obligar a quien llama a formatearlo) y aquí se manda solo su parte de
  /// fecha ("YYYY-MM-DD"), en la hora/zona LOCAL de `fechaLocal` (nunca
  /// `.toUtc()`: eso podría cambiar de día cerca de medianoche y sería
  /// exactamente la zona horaria equivocada — RF-23 es explícito en que
  /// debe ser la del dispositivo, no la de un servidor ni la de UTC).
  ///
  /// Regresa la insignia (RF-24, T-047) si ESTE intento fue el que completó
  /// el 100% del nivel, o null si no otorgó ninguna (ya la tenía de antes,
  /// o todavía falta alguna palabra).
  Future<Insignia?> guardarPractica({
    required int idPalabra,
    required int tiempoSegundos,
    required String oracionAlumno,
    required bool deletreoCorrecto,
    required DateTime fechaLocal,
    required String token,
  }) async {
    final json = await _api.post(
      '/practica',
      {
        'id_palabra': idPalabra,
        'tiempo_segundos': tiempoSegundos,
        'oracion_alumno': oracionAlumno,
        'deletreo_correcto': deletreoCorrecto,
        'fecha_local': formatearFechaLocal(fechaLocal),
      },
      token: token,
    );
    final insigniaJson = json['insignia_otorgada'] as Map<String, dynamic>?;
    return insigniaJson == null ? null : Insignia.desdeJson(insigniaJson);
  }

  /// RF-33 (T-062 cliente / T-063 servidor — este último todavía no existe):
  /// POST /practica/sync en lote. Mismos 5 campos que guardarPractica() más
  /// el `id` generado en el cliente (docs/diseno-tecnico.md §3.6), para que
  /// el futuro servidor pueda deduplicar un reintento sin duplicar el
  /// registro. Hasta que T-063 exista, esta llamada siempre falla (404 de
  /// ruta no encontrada, envuelto por ApiClient como un ApiException normal
  /// vía el filtro global de excepciones del backend) — comportamiento
  /// esperado, no un error de este método; ver SincronizadorPractica.
  Future<void> sincronizarLote(
    List<RegistroPracticaPendiente> registros,
    String token,
  ) {
    return _api.post('/practica/sync', {
      'registros': registros.map((r) => r.aJson()).toList(),
    }, token: token);
  }
}

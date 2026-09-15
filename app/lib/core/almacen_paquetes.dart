import 'paquete_nivel.dart';

/// Guarda/lee localmente el paquete descargado de un nivel (T-061, RF-31),
/// aparte de la app real por el mismo motivo que CacheAudio (ver ese
/// archivo): poder probarlo sin depender de un directorio real bajo
/// `flutter test`.
abstract class AlmacenPaquetes {
  Future<void> guardar(PaqueteNivel paquete);

  /// null si ese nivel todavía no se ha descargado.
  Future<PaqueteNivel?> obtener(int idNivel);

  /// RF-32: todos los paquetes ya descargados, sin necesidad de conocer de
  /// antemano sus ids (a diferencia de obtener()) — permite reconstruir qué
  /// niveles siguen disponibles para practicar aunque GET /niveles falle
  /// por falta de conexión (ver NivelesController.cargarInicial).
  Future<List<PaqueteNivel>> listarTodos();
}

/// Resuelve una url de audio a una ruta reproducible localmente, RNF-03:
/// reproducir en <2s cuando el archivo ya se descargó antes. Aparte de
/// ReproductorAudio por el mismo motivo que esa interfaz existe (ver
/// reproductor_audio.dart): para poder darle una versión falsa a las
/// pruebas sin depender de un directorio ni de red reales.
abstract class CacheAudio {
  /// [url] es la dirección completa desde la que descargar la primera vez
  /// (p. ej. "http://10.0.2.2:3000/assets/audios/1.mp3"). Si ya se había
  /// descargado antes, regresa la ruta local sin tocar la red; si no,
  /// la descarga primero, la guarda, y luego regresa la ruta local.
  Future<String> obtenerRutaLocal(String url);
}

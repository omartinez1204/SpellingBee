/// Estado de reproducción de un audio (T-030).
enum EstadoAudio {
  /// Nada reproduciéndose; el ícono debe verse como si nunca se hubiera
  /// tocado. Es el estado inicial, el de después de "detener" (RF-16) y el
  /// de después de que el audio termina solo (parte de RF-17: tiene que
  /// quedar listo para reproducirse de nuevo).
  detenido,

  /// Entre que se pide reproducir y que el audio realmente arranca.
  cargando,

  reproduciendo,
  pausado,
}

/// Envoltura mínima sobre el reproductor de audio real (just_audio),
/// exponiendo solo lo que T-030 necesita (RF-12/13/16/17). Igual que
/// FilePicker.platform en T-027: sin esta interfaz de por medio, la pantalla
/// dependería directamente de AudioPlayer y no habría forma de darle un
/// reproductor falso en un widget test (no hay canal de plataforma de audio
/// real bajo `flutter test`).
abstract class ReproductorAudio {
  Stream<EstadoAudio> get estado;

  /// RF-12. Cambiar de palabra a mitad de reproducción (llamar de nuevo con
  /// otra url) también debe funcionar — no es un caso que T-030 pida, pero
  /// tampoco hay que impedirlo.
  Future<void> reproducir(String url);

  /// RF-13 (mitad "pausar").
  Future<void> pausar();

  /// RF-13 (mitad "reanudar").
  Future<void> reanudar();

  /// RF-16. Debe dejar la posición en el inicio, no solo detener el sonido.
  Future<void> detener();

  /// RF-14. Exactamente 5 segundos hacia atrás, sin pasar del segundo 0.
  /// Válido mientras se reproduce o está pausada (no hay nada que retroceder
  /// en "detenido" o "cargando" — por eso la pantalla solo muestra este
  /// control en esos dos estados).
  Future<void> retroceder();

  /// RF-15. Exactamente 5 segundos hacia adelante, sin exceder la duración
  /// total del audio.
  Future<void> adelantar();

  /// RF-18. Tiempo transcurrido, para la barra de progreso y el texto
  /// mm:ss. Solo tiene que emitir mientras se reproduce — no hay nada que
  /// avanzar en pausa ni en detenido (la pantalla ya sabe reiniciar su
  /// propio valor mostrado a 0 cuando el estado pasa a "detenido").
  Stream<Duration> get posicion;

  /// RF-18. null hasta que el audio termine de cargar y se conozca su
  /// duración total.
  Stream<Duration?> get duracion;

  Future<void> dispose();
}

/// Estado de reproducción de un audio (T-030). No incluye posición/duración
/// todavía — eso es la barra de progreso de T-032.
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

  Future<void> dispose();
}

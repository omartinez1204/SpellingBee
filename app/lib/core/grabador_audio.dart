/// RF-40 (T-048): abstracción mínima sobre grabar → reproducir una vez →
/// borrar, para el botón "Escúchate" — mismo motivo que ReproductorAudio
/// (T-030): sin esto, la pantalla dependería directamente del micrófono y
/// de un reproductor reales, y no habría forma de darle una implementación
/// falsa en un widget test (no hay canal de plataforma de audio/micrófono
/// bajo `flutter test`).
abstract class GrabadorAudio {
  /// Pide el permiso de micrófono si todavía no se ha concedido — el propio
  /// sistema operativo decide si de verdad hace falta mostrar el diálogo
  /// nativo o no (RNF §3.1.2: "se solicita solo la primera vez que el
  /// alumno use el botón 'Escúchate'"). true si el permiso quedó concedido.
  Future<bool> solicitarPermiso();

  /// Empieza a grabar a un archivo temporal. Debe llamarse solo después de
  /// que [solicitarPermiso] haya regresado true.
  Future<void> iniciarGrabacion();

  /// Detiene la grabación, reproduce el resultado una sola vez, y borra el
  /// archivo del dispositivo apenas termina de reproducirse — no regresa
  /// hasta que las tres cosas ya pasaron. RF-40: "la reproduce una vez... y
  /// la elimina del dispositivo inmediatamente después".
  Future<void> detenerYReproducir();

  /// Libera los recursos de grabación/reproducción y, si quedó una
  /// grabación a medias (el alumno salió de la pantalla antes de llegar a
  /// [detenerYReproducir]), la descarta sin dejar el archivo en el
  /// dispositivo.
  Future<void> dispose();
}

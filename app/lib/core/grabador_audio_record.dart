import 'dart:io';

import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'grabador_audio.dart';

/// Implementación real de GrabadorAudio (T-048/RF-40) con los 3 paquetes
/// que señala docs/diseno-tecnico.md §3.4: record (captura), just_audio
/// (reproducción, ya usado por T-030) y permission_handler (permiso de
/// micrófono).
///
/// SIN LLAMADAS DE RED: esta clase solo toca el micrófono (record), un
/// archivo LOCAL (dart:io / setFilePath — nunca una url ni ApiClient) y el
/// directorio de CACHÉ del propio dispositivo (path_provider). El archivo
/// vive en getTemporaryDirectory(), no en getApplicationDocumentsDirectory
/// ni en ninguna carpeta que se respalde o sincronice (RF-40: "estrictamente
/// local"), y se borra apenas termina de reproducirse — nunca llega a
/// PracticaService ni a ningún otro código que hable con el backend.
class GrabadorAudioRecord implements GrabadorAudio {
  final AudioRecorder _grabador = AudioRecorder();
  final just_audio.AudioPlayer _reproductor = just_audio.AudioPlayer();

  @override
  Future<bool> solicitarPermiso() async {
    final estado = await Permission.microphone.request();
    return estado.isGranted;
  }

  @override
  Future<void> iniciarGrabacion() async {
    final directorio = await getTemporaryDirectory();
    // Nombre único por intento (timestamp): si algo dejara un archivo
    // huérfano de un intento anterior, el siguiente no lo pisa ni lo
    // confunde consigo mismo.
    final ruta =
        '${directorio.path}/escuchate_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _grabador.start(const RecordConfig(), path: ruta);
  }

  @override
  Future<void> detenerYReproducir() async {
    final ruta = await _grabador.stop();
    if (ruta == null) return;
    try {
      await _reproductor.setFilePath(ruta);
      await _reproductor.play();
      // RF-40: se reproduce UNA sola vez — esperar el fin natural antes de
      // borrar, no un tiempo fijo adivinado.
      await _reproductor.playerStateStream.firstWhere(
        (estado) =>
            estado.processingState == just_audio.ProcessingState.completed,
      );
    } finally {
      final archivo = File(ruta);
      if (await archivo.exists()) await archivo.delete();
    }
  }

  @override
  Future<void> dispose() async {
    // AudioRecorder.cancel() detiene Y borra el archivo si había una
    // grabación en curso (el alumno salió de la pantalla sin llegar a
    // "Detener") — sin esto, ese archivo se quedaría huérfano en el
    // dispositivo, violando la misma garantía de RF-40.
    await _grabador.cancel();
    await _reproductor.stop();
    await _grabador.dispose();
    await _reproductor.dispose();
  }
}

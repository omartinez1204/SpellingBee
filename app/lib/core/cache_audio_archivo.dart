import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cache_audio.dart';

/// Implementación real de CacheAudio: un archivo por palabra dentro del
/// directorio de caché de la app (el sistema operativo puede borrarlo bajo
/// presión de espacio — está bien, es contenido redescargable, no algo que
/// deba respaldarse).
///
/// La clave de caché es el último segmento de la url (p. ej. "1.mp3"). Sirve
/// tal cual porque el backend ya nombra el audio de cada palabra por su id,
/// nunca por su texto (T-025, ver docs/CLAUDE.md) — no hay choque posible
/// entre palabras distintas, y corregir la ortografía de una palabra (RF-09)
/// no puede dejar servido un audio viejo bajo el mismo nombre.
class CacheAudioArchivo implements CacheAudio {
  CacheAudioArchivo({http.Client? httpClient, Future<Directory> Function()? directorio})
    : _http = httpClient ?? http.Client(),
      _directorio = directorio ?? getApplicationCacheDirectory;

  final http.Client _http;
  final Future<Directory> Function() _directorio;

  @override
  Future<String> obtenerRutaLocal(String url) async {
    final nombreArchivo = Uri.parse(url).pathSegments.last;
    final base = await _directorio();
    final destino = File('${base.path}/audios_cache/$nombreArchivo');

    if (await destino.exists()) {
      return destino.path;
    }

    final respuesta = await _http.get(Uri.parse(url));
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw Exception(
        'No se pudo descargar el audio (${respuesta.statusCode}).',
      );
    }

    // Se escribe primero a un .tmp y se renombra al final: si la descarga
    // se interrumpe a la mitad (la app se cierra, se corta la conexión), lo
    // que queda tirado es el .tmp — nunca un audio a medias en la ruta que
    // la próxima llamada toma como "ya está cacheado" y ya no vuelve a
    // pedir.
    await destino.parent.create(recursive: true);
    final temporal = File('${destino.path}.tmp');
    await temporal.writeAsBytes(respuesta.bodyBytes);
    await temporal.rename(destino.path);

    return destino.path;
  }
}

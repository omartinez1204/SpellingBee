import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'almacen_paquetes.dart';
import 'paquete_nivel.dart';

/// Implementación real de AlmacenPaquetes: un archivo JSON por nivel.
///
/// A diferencia de CacheAudioArchivo (que guarda los audios en el
/// directorio de CACHÉ, purgable por el SO bajo presión de espacio — ver
/// ese archivo, es aceptable porque el audio es redescargable) esto usa el
/// directorio de SOPORTE de la app: si el alumno descargó un nivel para
/// practicar sin conexión, "¿ya lo descargué?" debe sobrevivir mientras
/// esté sin conexión, no perderse por una limpieza de caché del sistema.
class AlmacenPaquetesArchivo implements AlmacenPaquetes {
  AlmacenPaquetesArchivo({Future<Directory> Function()? directorio})
    : _directorio = directorio ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directorio;

  Future<File> _archivo(int idNivel) async {
    final base = await _directorio();
    return File('${base.path}/niveles_descargados/$idNivel.json');
  }

  @override
  Future<void> guardar(PaqueteNivel paquete) async {
    final archivo = await _archivo(paquete.nivel.id);
    await archivo.parent.create(recursive: true);
    // Mismo patrón .tmp + rename que CacheAudioArchivo: si la escritura se
    // interrumpe a medias, lo que queda tirado es el .tmp — nunca un JSON a
    // medio escribir en la ruta que obtener() ya trataría como "descarga
    // completa".
    final temporal = File('${archivo.path}.tmp');
    await temporal.writeAsString(jsonEncode(paquete.aJson()));
    await temporal.rename(archivo.path);
  }

  @override
  Future<PaqueteNivel?> obtener(int idNivel) async {
    final archivo = await _archivo(idNivel);
    if (!await archivo.exists()) return null;
    final contenido = await archivo.readAsString();
    return PaqueteNivel.desdeJson(
      jsonDecode(contenido) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<PaqueteNivel>> listarTodos() async {
    final base = await _directorio();
    final carpeta = Directory('${base.path}/niveles_descargados');
    if (!await carpeta.exists()) return [];

    final paquetes = <PaqueteNivel>[];
    await for (final entidad in carpeta.list()) {
      // Ignora los .tmp de una escritura interrumpida a medias (ver
      // guardar()) — nunca representan una descarga completa.
      if (entidad is! File || !entidad.path.endsWith('.json')) continue;
      final contenido = await entidad.readAsString();
      paquetes.add(
        PaqueteNivel.desdeJson(jsonDecode(contenido) as Map<String, dynamic>),
      );
    }
    return paquetes;
  }
}

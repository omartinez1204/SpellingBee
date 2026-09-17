import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cola_practica.dart';
import 'registro_practica_pendiente.dart';

/// Implementación real de ColaPractica: UN archivo JSON con el arreglo
/// completo de pendientes, en el directorio de SOPORTE de la app — mismo
/// criterio que AlmacenPaquetesArchivo (ver ese archivo): un registro de
/// práctica sin sincronizar debe sobrevivir una limpieza de caché del SO, no
/// solo un cierre normal de la app, y desde luego debe sobrevivir cerrar y
/// reabrir la app (RF-33: "sin descartar ningún registro... mientras no se
/// confirme su envío exitoso").
///
/// agregar()/eliminar() se serializan entre sí con un Future encadenado a
/// modo de mutex: ambos son lectura-modificación-escritura del MISMO archivo
/// completo, y sin esto dos llamadas concurrentes (p. ej. el alumno termina
/// una práctica offline justo cuando el sincronizador ya está a medio mandar
/// un lote anterior y a punto de eliminar lo ya confirmado) podrían perder
/// la escritura de una de las dos — justo lo que RF-33 prohíbe. El patrón
/// .tmp + rename, igual que en el resto del código, evita que una escritura
/// interrumpida a medias deje el archivo dañado.
class ColaPracticaArchivo implements ColaPractica {
  ColaPracticaArchivo({Future<Directory> Function()? directorio})
    : _directorio = directorio ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directorio;

  /// Cola de operaciones: cada llamada pública se encadena sobre la
  /// anterior, sin importar si esa anterior tuvo éxito o falló (ver
  /// _encolarOperacion) — así nunca hay dos lecturas-modificación-escritura
  /// del archivo completo corriendo en paralelo dentro del mismo proceso.
  Future<void> _ultimaOperacion = Future.value();

  Future<File> _archivo() async {
    final base = await _directorio();
    return File('${base.path}/cola_practica_pendiente.json');
  }

  Future<T> _encolarOperacion<T>(Future<T> Function() operacion) {
    final resultado = _ultimaOperacion.then((_) => operacion());
    // La cadena debe seguir viva aunque operacion() falle — si no,
    // un solo fallo dejaría el mutex trabado para siempre y ninguna llamada
    // futura avanzaría. Quien llamó a esta función sigue viendo el error
    // real a través de `resultado`, no de esta rama.
    _ultimaOperacion = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  Future<List<RegistroPracticaPendiente>> _leerTodosSinBloqueo() async {
    final archivo = await _archivo();
    if (!await archivo.exists()) return [];
    final contenido = await archivo.readAsString();
    final lista = jsonDecode(contenido) as List<dynamic>;
    return lista
        .map(
          (item) =>
              RegistroPracticaPendiente.desdeJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> _escribirTodos(List<RegistroPracticaPendiente> registros) async {
    final archivo = await _archivo();
    await archivo.parent.create(recursive: true);
    final temporal = File('${archivo.path}.tmp');
    await temporal.writeAsString(
      jsonEncode(registros.map((r) => r.aJson()).toList()),
    );
    await temporal.rename(archivo.path);
  }

  @override
  Future<void> agregar(RegistroPracticaPendiente registro) {
    return _encolarOperacion(() async {
      final actuales = await _leerTodosSinBloqueo();
      actuales.add(registro);
      await _escribirTodos(actuales);
    });
  }

  @override
  Future<void> eliminar(String id) {
    return _encolarOperacion(() async {
      final actuales = await _leerTodosSinBloqueo();
      actuales.removeWhere((registro) => registro.id == id);
      await _escribirTodos(actuales);
    });
  }

  @override
  Future<List<RegistroPracticaPendiente>> listarPendientes() {
    return _encolarOperacion(_leerTodosSinBloqueo);
  }
}

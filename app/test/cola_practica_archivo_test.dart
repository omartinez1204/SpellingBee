import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/cola_practica_archivo.dart';
import 'package:spelling_bee/core/registro_practica_pendiente.dart';

// T-062 (RF-33): ColaPracticaArchivo es la parte de "cola local de registros
// de práctica offline" que se puede probar sin dispositivo real: dado un
// directorio de verdad (uno temporal, propio de cada prueba), decide qué
// queda guardado y qué se lee de vuelta, y que dos operaciones concurrentes
// nunca se pisen entre sí. Que la app en verdad encole un registro cuando
// falla POST /practica sin conexión se probó a mano en dispositivo (ver el
// reporte de esta tarea), no aquí.
void main() {
  late Directory directorioTemporal;

  setUp(() async {
    directorioTemporal = await Directory.systemTemp.createTemp(
      'cola_practica_test_',
    );
  });

  tearDown(() async {
    if (await directorioTemporal.exists()) {
      await directorioTemporal.delete(recursive: true);
    }
  });

  ColaPracticaArchivo crear() =>
      ColaPracticaArchivo(directorio: () async => directorioTemporal);

  RegistroPracticaPendiente registroDePrueba({
    String id = 'id-1',
    int idPalabra = 10,
  }) {
    return RegistroPracticaPendiente(
      id: id,
      idPalabra: idPalabra,
      tiempoSegundos: 42,
      oracionAlumno: 'This is my business.',
      deletreoCorrecto: true,
      fechaLocal: '2026-09-15',
    );
  }

  test('listarPendientes() regresa vacío si nunca se ha encolado nada (ni existe el archivo)', () async {
    final cola = crear();
    expect(await cola.listarPendientes(), isEmpty);
  });

  test('agregar() y luego listarPendientes() regresan exactamente ese registro', () async {
    final cola = crear();
    final registro = registroDePrueba();

    await cola.agregar(registro);
    final pendientes = await cola.listarPendientes();

    expect(pendientes, hasLength(1));
    expect(pendientes.single.id, registro.id);
    expect(pendientes.single.idPalabra, registro.idPalabra);
    expect(pendientes.single.tiempoSegundos, registro.tiempoSegundos);
    expect(pendientes.single.oracionAlumno, registro.oracionAlumno);
    expect(pendientes.single.deletreoCorrecto, registro.deletreoCorrecto);
    expect(pendientes.single.fechaLocal, registro.fechaLocal);
  });

  test('agregar() varias veces acumula, no sobrescribe (a diferencia de AlmacenPaquetes)', () async {
    final cola = crear();
    await cola.agregar(registroDePrueba(id: 'id-1', idPalabra: 10));
    await cola.agregar(registroDePrueba(id: 'id-2', idPalabra: 11));
    await cola.agregar(registroDePrueba(id: 'id-3', idPalabra: 12));

    final pendientes = await cola.listarPendientes();

    expect(pendientes.map((r) => r.id).toSet(), {'id-1', 'id-2', 'id-3'});
  });

  test('eliminar() quita solo el registro indicado, deja los demás intactos', () async {
    final cola = crear();
    await cola.agregar(registroDePrueba(id: 'id-1', idPalabra: 10));
    await cola.agregar(registroDePrueba(id: 'id-2', idPalabra: 11));
    await cola.agregar(registroDePrueba(id: 'id-3', idPalabra: 12));

    await cola.eliminar('id-2');

    final pendientes = await cola.listarPendientes();
    expect(pendientes.map((r) => r.id).toSet(), {'id-1', 'id-3'});
  });

  test('eliminar() un id que no existe no falla y no toca nada', () async {
    final cola = crear();
    await cola.agregar(registroDePrueba());

    await cola.eliminar('id-que-no-existe');

    expect(await cola.listarPendientes(), hasLength(1));
  });

  test(
    'RF-33: lo encolado sobrevive una sesión nueva sobre el mismo directorio (cerrar y reabrir la app)',
    () async {
      final sesion1 = crear();
      await sesion1.agregar(registroDePrueba(id: 'id-1'));

      final sesion2 = crear();
      final pendientes = await sesion2.listarPendientes();

      expect(pendientes, hasLength(1));
      expect(pendientes.single.id, 'id-1');
    },
  );

  test(
    'RF-33: dos operaciones concurrentes (agregar + eliminar) nunca pierden una escritura',
    () async {
      final cola = crear();
      await cola.agregar(registroDePrueba(id: 'ya-estaba'));

      // Sin esperar entre sí a propósito: agregar() e eliminar() son
      // lectura-modificación-escritura del MISMO archivo — si no estuvieran
      // serializadas entre sí, una de las dos escrituras podría perderse
      // (justo lo que el mutex de ColaPracticaArchivo evita).
      await Future.wait([
        cola.agregar(registroDePrueba(id: 'nuevo')),
        cola.eliminar('ya-estaba'),
      ]);

      final pendientes = await cola.listarPendientes();
      expect(
        pendientes.map((r) => r.id).toSet(),
        {'nuevo'},
        reason:
            'ninguna de las dos operaciones debió perderse ni pisar a la otra',
      );
    },
  );

  test('un .tmp abandonado de una escritura interrumpida no se confunde con la cola real', () async {
    await File(
      '${directorioTemporal.path}/cola_practica_pendiente.json.tmp',
    ).writeAsString('a medias');

    final cola = crear();

    expect(
      await cola.listarPendientes(),
      isEmpty,
      reason: 'el .tmp no cuenta como cola ya escrita',
    );
  });

  test('agregar() no deja un .tmp huérfano tras una escritura exitosa', () async {
    final cola = crear();
    await cola.agregar(registroDePrueba());

    final tmp = File(
      '${directorioTemporal.path}/cola_practica_pendiente.json.tmp',
    );
    expect(await tmp.exists(), isFalse);
  });

  test('el JSON persistido usa las mismas claves snake_case que POST /practica', () async {
    final cola = crear();
    await cola.agregar(registroDePrueba());

    final crudo = await File(
      '${directorioTemporal.path}/cola_practica_pendiente.json',
    ).readAsString();
    final decodificado = jsonDecode(crudo) as List<dynamic>;

    expect(decodificado, hasLength(1));
    final primero = decodificado.single as Map<String, dynamic>;
    expect(primero['id'], 'id-1');
    expect(primero['id_palabra'], 10);
    expect(primero['tiempo_segundos'], 42);
    expect(primero['oracion_alumno'], 'This is my business.');
    expect(primero['deletreo_correcto'], true);
    expect(primero['fecha_local'], '2026-09-15');
  });
}

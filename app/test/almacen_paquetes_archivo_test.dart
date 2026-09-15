import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/almacen_paquetes_archivo.dart';
import 'package:spelling_bee/core/detalle_palabra.dart';
import 'package:spelling_bee/core/nivel.dart';
import 'package:spelling_bee/core/paquete_nivel.dart';

// T-061 (RF-31): AlmacenPaquetesArchivo es la parte de "descarga y
// almacenamiento local del paquete de un nivel" que se puede probar sin
// dispositivo real: dado un directorio de verdad (uno temporal, propio de
// cada prueba), decide qué queda guardado y qué se lee de vuelta. Que la
// pantalla de práctica en verdad funcione con esto en modo avión se probó
// a mano en dispositivo (ver el reporte de esta tarea), no aquí.
void main() {
  late Directory directorioTemporal;

  setUp(() async {
    directorioTemporal = await Directory.systemTemp.createTemp(
      'almacen_paquetes_test_',
    );
  });

  tearDown(() async {
    if (await directorioTemporal.exists()) {
      await directorioTemporal.delete(recursive: true);
    }
  });

  AlmacenPaquetesArchivo crear() =>
      AlmacenPaquetesArchivo(directorio: () async => directorioTemporal);

  PaqueteNivel paqueteDePrueba({
    int idNivel = 2,
    String nombreNivel = 'Fácil',
  }) {
    return PaqueteNivel(
      nivel: Nivel(id: idNivel, nombre: nombreNivel, orden: 1),
      palabras: const [
        DetallePalabra(
          id: 10,
          texto: 'business',
          significadoEs: 'negocio',
          oracionEjemplo: 'This is my business.',
          urlAudio: '/assets/audios/10.mp3',
        ),
        DetallePalabra(
          id: 11,
          texto: 'apple',
          significadoEs: null,
          oracionEjemplo: null,
          urlAudio: null,
        ),
      ],
    );
  }

  test('obtener() de un nivel nunca guardado regresa null', () async {
    final almacen = crear();
    expect(await almacen.obtener(999), isNull);
  });

  test(
    'guardar() y luego obtener() regresan exactamente el mismo paquete',
    () async {
      final almacen = crear();
      final paquete = paqueteDePrueba();

      await almacen.guardar(paquete);
      final leido = await almacen.obtener(paquete.nivel.id);

      expect(leido, isNotNull);
      expect(leido!.nivel.id, paquete.nivel.id);
      expect(leido.nivel.nombre, paquete.nivel.nombre);
      expect(leido.palabras, hasLength(2));
      expect(leido.palabras[0].id, 10);
      expect(leido.palabras[0].texto, 'business');
      expect(leido.palabras[0].significadoEs, 'negocio');
      expect(leido.palabras[0].oracionEjemplo, 'This is my business.');
      expect(leido.palabras[0].urlAudio, '/assets/audios/10.mp3');
      // Palabra con campos opcionales en null también sobrevive el
      // redondeo por JSON tal cual (no se convierten a cadena vacía).
      expect(leido.palabras[1].significadoEs, isNull);
      expect(leido.palabras[1].urlAudio, isNull);
    },
  );

  test('guardar() dos veces el mismo nivel sobrescribe, no duplica', () async {
    final almacen = crear();
    await almacen.guardar(paqueteDePrueba());
    await almacen.guardar(
      PaqueteNivel(
        nivel: const Nivel(id: 2, nombre: 'Fácil', orden: 1),
        palabras: const [
          DetallePalabra(
            id: 99,
            texto: 'nuevo',
            significadoEs: null,
            oracionEjemplo: null,
            urlAudio: null,
          ),
        ],
      ),
    );

    final leido = await almacen.obtener(2);
    expect(leido!.palabras, hasLength(1));
    expect(leido.palabras.single.id, 99);

    final todos = await almacen.listarTodos();
    expect(todos, hasLength(1), reason: 'no debe quedar un duplicado');
  });

  test(
    'listarTodos() regresa lista vacía si nunca se ha guardado nada (ni existe la carpeta)',
    () async {
      final almacen = crear();
      expect(await almacen.listarTodos(), isEmpty);
    },
  );

  test(
    'listarTodos() regresa todos los niveles guardados, RF-32: sin necesitar conocer sus ids de antemano',
    () async {
      final almacen = crear();
      await almacen.guardar(paqueteDePrueba(idNivel: 2, nombreNivel: 'Fácil'));
      await almacen.guardar(
        paqueteDePrueba(idNivel: 3, nombreNivel: 'Intermedio'),
      );

      final todos = await almacen.listarTodos();

      expect(todos, hasLength(2));
      expect(
        todos.map((p) => p.nivel.id).toSet(),
        {2, 3},
      );
    },
  );

  test(
    'un .tmp abandonado de una escritura interrumpida no se confunde con un paquete válido',
    () async {
      final carpeta = Directory(
        '${directorioTemporal.path}/niveles_descargados',
      );
      await carpeta.create(recursive: true);
      await File('${carpeta.path}/2.json.tmp').writeAsString('a medias');

      final almacen = crear();

      expect(
        await almacen.obtener(2),
        isNull,
        reason: 'el .tmp no cuenta como el nivel 2 ya descargado',
      );
      expect(
        await almacen.listarTodos(),
        isEmpty,
        reason: 'listarTodos() tampoco debe confundir el .tmp con un paquete',
      );
    },
  );

  test(
    'guardar() no dejar un .tmp huérfano tras una escritura exitosa',
    () async {
      final almacen = crear();
      await almacen.guardar(paqueteDePrueba());

      final tmp = File(
        '${directorioTemporal.path}/niveles_descargados/2.json.tmp',
      );
      expect(await tmp.exists(), isFalse);
    },
  );

  test('el JSON persistido usa las mismas claves snake_case del backend', () async {
    final almacen = crear();
    await almacen.guardar(paqueteDePrueba());

    final crudo = await File(
      '${directorioTemporal.path}/niveles_descargados/2.json',
    ).readAsString();
    final decodificado = jsonDecode(crudo) as Map<String, dynamic>;

    expect(decodificado['nivel'], {'id': 2, 'nombre': 'Fácil', 'orden': 1});
    final primeraPalabra =
        (decodificado['palabras'] as List<dynamic>).first
            as Map<String, dynamic>;
    expect(primeraPalabra['significado_es'], 'negocio');
    expect(primeraPalabra['oracion_ejemplo'], 'This is my business.');
    expect(primeraPalabra['url_audio'], '/assets/audios/10.mp3');
  });
}

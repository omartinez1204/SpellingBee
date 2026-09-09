import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spelling_bee/core/cache_audio_archivo.dart';

// CacheAudioArchivo es la parte de T-033 (RNF-03) que sí se puede probar sin
// AudioPlayer real: dado un http.Client falso y un directorio de verdad
// (uno temporal, propio de cada prueba, no el de la app), decide cuándo
// pedir red y cuándo no. La verificación de que la app en verdad reproduce
// <2s la segunda vez, y que no depende de red estando el backend caído, se
// hizo a mano en dispositivo, no aquí.
void main() {
  late Directory directorioTemporal;

  setUp(() async {
    directorioTemporal = await Directory.systemTemp.createTemp(
      'cache_audio_test_',
    );
  });

  tearDown(() async {
    if (await directorioTemporal.exists()) {
      await directorioTemporal.delete(recursive: true);
    }
  });

  CacheAudioArchivo crear({required http.Client httpClient}) =>
      CacheAudioArchivo(
        httpClient: httpClient,
        directorio: () async => directorioTemporal,
      );

  test(
    'si el audio no está en caché, lo descarga y guarda una sola vez',
    () async {
      var vecesLlamado = 0;
      final bytesEsperados = utf8.encode('contenido-de-audio-falso');
      final cliente = MockClient((request) async {
        vecesLlamado++;
        return http.Response.bytes(bytesEsperados, 200);
      });

      final cache = crear(httpClient: cliente);
      final ruta = await cache.obtenerRutaLocal(
        'http://10.0.2.2:3000/assets/audios/1.mp3',
      );

      expect(vecesLlamado, 1);
      expect(await File(ruta).readAsBytes(), bytesEsperados);
    },
  );

  test(
    'RNF-03: si el audio ya está en caché, no vuelve a pedirlo por red',
    () async {
      var vecesLlamado = 0;
      final cliente = MockClient((request) async {
        vecesLlamado++;
        return http.Response.bytes(utf8.encode('nuevo'), 200);
      });
      final cache = crear(httpClient: cliente);

      final rutaPrimeraVez = await cache.obtenerRutaLocal(
        'http://10.0.2.2:3000/assets/audios/1.mp3',
      );
      expect(vecesLlamado, 1);

      final rutaSegundaVez = await cache.obtenerRutaLocal(
        'http://10.0.2.2:3000/assets/audios/1.mp3',
      );

      expect(vecesLlamado, 1, reason: 'la segunda vez no debe tocar la red');
      expect(rutaSegundaVez, rutaPrimeraVez);
    },
  );

  test('usa el último segmento de la url como nombre de archivo', () async {
    final cliente = MockClient(
      (request) async => http.Response.bytes(utf8.encode('x'), 200),
    );
    final cache = crear(httpClient: cliente);

    final ruta = await cache.obtenerRutaLocal(
      'http://10.0.2.2:3000/assets/audios/7.mp3',
    );

    expect(ruta.endsWith('7.mp3'), isTrue);
  });

  test(
    'una respuesta de error del servidor no deja caché falso y lanza',
    () async {
      final cliente = MockClient(
        (request) async => http.Response('no encontrado', 404),
      );
      final cache = crear(httpClient: cliente);
      const url = 'http://10.0.2.2:3000/assets/audios/1.mp3';

      await expectLater(cache.obtenerRutaLocal(url), throwsException);

      // Un intento posterior (p. ej. tras subir el audio real) debe poder
      // volver a intentarlo — no debe haber quedado un archivo a medias
      // marcado como si ya estuviera cacheado.
      var vecesLlamado = 0;
      final cache2 = CacheAudioArchivo(
        httpClient: MockClient((request) async {
          vecesLlamado++;
          return http.Response.bytes(utf8.encode('ok'), 200);
        }),
        directorio: () async => directorioTemporal,
      );
      await cache2.obtenerRutaLocal(url);
      expect(vecesLlamado, 1);
    },
  );

  test(
    'un .tmp abandonado de una descarga previa interrumpida no se confunde con caché válida',
    () async {
      final destino = File(
        '${directorioTemporal.path}/audios_cache/1.mp3.tmp',
      );
      await destino.parent.create(recursive: true);
      await destino.writeAsBytes(utf8.encode('a medias'));

      var vecesLlamado = 0;
      final bytesCompletos = utf8.encode('archivo-completo');
      final cliente = MockClient((request) async {
        vecesLlamado++;
        return http.Response.bytes(bytesCompletos, 200);
      });
      final cache = crear(httpClient: cliente);

      final ruta = await cache.obtenerRutaLocal(
        'http://10.0.2.2:3000/assets/audios/1.mp3',
      );

      expect(vecesLlamado, 1, reason: 'el .tmp viejo no cuenta como caché');
      expect(await File(ruta).readAsBytes(), bytesCompletos);
      expect(await destino.exists(), isFalse, reason: 'el .tmp se consume al renombrar');
    },
  );
}

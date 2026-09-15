import 'package:flutter/foundation.dart';

import 'almacen_paquetes.dart';
import 'almacen_paquetes_archivo.dart';
import 'api_exception.dart';
import 'cache_audio.dart';
import 'cache_audio_archivo.dart';
import 'nivel.dart';
import 'niveles_service.dart';
import 'paquete_nivel.dart';

/// Estado de la pantalla de niveles para practicar (T-061, RF-31/RF-32):
/// lista los 3 niveles (RF-05) y, por cada uno, si ya está descargado
/// localmente. Descargar un nivel trae su paquete completo (T-060, texto +
/// significado + oración de cada palabra) y precachea CADA audio con el
/// MISMO CacheAudio que ya usa el reproductor (T-033, RNF-03) — así, cuando
/// la pantalla de práctica pida reproducir esa palabra más tarde, el
/// archivo YA está en el disco bajo la misma clave (nombre de archivo) que
/// el reproductor busca, y la llamada nunca toca la red, sin importar si
/// hay conexión en ese momento (RF-32).
class NivelesController extends ChangeNotifier {
  NivelesController({
    required this.token,
    NivelesService? nivelesService,
    AlmacenPaquetes? almacen,
    CacheAudio? cacheAudio,
  }) : _nivelesService = nivelesService ?? NivelesService(),
       _almacen = almacen ?? AlmacenPaquetesArchivo(),
       _cacheAudio = cacheAudio ?? CacheAudioArchivo();

  final String token;
  final NivelesService _nivelesService;
  final AlmacenPaquetes _almacen;
  final CacheAudio _cacheAudio;

  List<Nivel> _niveles = [];
  List<Nivel> get niveles => List.unmodifiable(_niveles);

  final Map<int, PaqueteNivel> _paquetesLocales = {};
  PaqueteNivel? paqueteLocal(int idNivel) => _paquetesLocales[idNivel];
  bool estaDescargado(int idNivel) => _paquetesLocales.containsKey(idNivel);

  final Set<int> _descargando = {};
  bool estaDescargando(int idNivel) => _descargando.contains(idNivel);

  final Map<int, String> _erroresDescarga = {};
  String? errorDescarga(int idNivel) => _erroresDescarga[idNivel];

  bool _cargando = false;
  bool get cargando => _cargando;
  String? _error;
  String? get error => _error;

  // RF-32: si el alumno abre esta pantalla YA sin conexión (no es que se
  // desconectó a medio uso), GET /niveles falla — pero eso no debe dejarlo
  // sin poder llegar a un nivel que ya había descargado antes. Por eso, si
  // listar() falla, se reconstruye la lista visible a partir de lo que haya
  // en AlmacenPaquetes.listarTodos() (que no necesita red ni conocer ids de
  // antemano) en vez de mostrar solo un error — el error real ("no se pudo
  // cargar la lista de niveles") solo se muestra si tampoco hay nada
  // descargado localmente, es decir, si de verdad no hay nada que ofrecer.
  Future<void> cargarInicial() async {
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final niveles = await _nivelesService.listar();
      final paquetes = <int, PaqueteNivel>{};
      for (final nivel in niveles) {
        final local = await _almacen.obtener(nivel.id);
        if (local != null) paquetes[nivel.id] = local;
      }
      _niveles = niveles;
      _paquetesLocales
        ..clear()
        ..addAll(paquetes);
    } on ApiException catch (e) {
      final locales = await _almacen.listarTodos();
      if (locales.isEmpty) {
        _error = e.message;
      } else {
        locales.sort((a, b) => a.nivel.orden.compareTo(b.nivel.orden));
        _niveles = locales.map((paquete) => paquete.nivel).toList();
        _paquetesLocales
          ..clear()
          ..addAll({for (final p in locales) p.nivel.id: p});
      }
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  // RF-31: descarga el paquete completo del nivel (palabras + audios) y lo
  // deja disponible para practicar sin conexión.
  //
  // Todo o nada [decisión de equipo, a confirmar]: si un solo audio falla a
  // medio camino, NO se marca el nivel como descargado — un paquete a
  // medias (algunas palabras con audio local, otras sin él) dejaría
  // "reproducir audio" roto para esas palabras, violando RF-32 ("todas las
  // funciones de práctica... para el contenido ya descargado"). Los audios
  // que sí alcanzaron a guardarse quedan en caché de todas formas
  // (CacheAudioArchivo ya es idempotente por archivo, T-033), así que
  // reintentar la descarga no vuelve a pedirlos por red.
  Future<void> descargar(int idNivel) async {
    if (_descargando.contains(idNivel)) return;
    _descargando.add(idNivel);
    _erroresDescarga.remove(idNivel);
    notifyListeners();
    try {
      final paquete = await _nivelesService.obtenerDescarga(idNivel);
      for (final palabra in paquete.palabras) {
        final urlAudio = palabra.urlAudio;
        if (urlAudio == null) continue;
        await _cacheAudio.obtenerRutaLocal(
          '${_nivelesService.baseUrl}$urlAudio',
        );
      }
      await _almacen.guardar(paquete);
      _paquetesLocales[idNivel] = paquete;
    } on ApiException catch (e) {
      _erroresDescarga[idNivel] = e.message;
    } catch (_) {
      // CacheAudio.obtenerRutaLocal no pasa por ApiClient (usa http.Client
      // directo, ver cache_audio_archivo.dart) — sus fallos de red no vienen
      // envueltos en ApiException, así que este catch-all es necesario para
      // no dejar la descarga "colgada" en estado _descargando para siempre.
      _erroresDescarga[idNivel] =
          'No se pudo descargar el contenido de este nivel. '
          'Verifica tu conexión e intenta de nuevo.';
    } finally {
      _descargando.remove(idNivel);
      notifyListeners();
    }
  }
}

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'cache_audio.dart';
import 'cache_audio_archivo.dart';
import 'reproductor_audio.dart';

// RF-14/RF-15: el valor exacto (5s) lo confirmó el cliente, no es ajustable.
const _saltoSegundos = Duration(seconds: 5);

/// Aparte para poder probarla sin AudioPlayer real (no hay canal de
/// plataforma de audio bajo `flutter test`, así que cualquier prueba tiene
/// que evitar tocar la instancia de just_audio). El criterio de RF-14/RF-15
/// es exactamente esto: mover 5 segundos sin pasar de 0 ni de la duración.
Duration posicionTrasSalto({
  required Duration actual,
  required Duration delta,
  required Duration? duracion,
}) {
  var nueva = actual + delta;
  if (nueva < Duration.zero) nueva = Duration.zero;
  if (duracion != null && nueva > duracion) nueva = duracion;
  return nueva;
}

/// Implementación real de ReproductorAudio con el paquete just_audio.
///
/// just_audio.AudioPlayer.stop() documenta explícitamente que "the current
/// audio source state will be retained" — es decir, NO regresa la posición a
/// 0 por su cuenta. RF-16 exige que sí ("el indicador vuelve al inicio de la
/// pista"), así que detener() hace stop()+seek(cero) a propósito, no es
/// redundante.
///
/// Igual de importante: la documentación de play() aclara que, cuando el
/// audio termina solo, `playing` se queda en true (para que un seek()
/// posterior pueda seguir reproduciendo desde ahí si se quisiera). Como
/// RF-17 necesita que la palabra quede lista para repetirse — no en loop
/// automático — hay que reaccionar al estado "completed" nosotros mismos:
/// pausar y regresar a 0, igual que un detener() manual.
///
/// T-033 (RNF-03): reproducir() nunca reproduce directo de la url remota —
/// primero pasa por CacheAudio, que descarga y guarda la primera vez y
/// regresa la copia local de inmediato las siguientes.
class ReproductorAudioJustAudio implements ReproductorAudio {
  ReproductorAudioJustAudio({CacheAudio? cacheAudio})
    : _cache = cacheAudio ?? CacheAudioArchivo() {
    _suscripcion = _reproductor.playerStateStream.listen(_alCambiarEstado);
  }

  final AudioPlayer _reproductor = AudioPlayer();
  final CacheAudio _cache;
  final _controlador = StreamController<EstadoAudio>.broadcast();
  late final StreamSubscription<PlayerState> _suscripcion;

  // Mientras se ejecuta _reiniciar(), se ignoran los eventos intermedios que
  // el propio stop()/pause()+seek() dispara (p. ej. un "pausado" transitorio
  // entre el pause y el seek) — el único estado válido al terminar es
  // "detenido", emitido a mano al final.
  bool _reiniciando = false;

  @override
  Stream<EstadoAudio> get estado => _controlador.stream;

  // RF-18. positionStream de just_audio ya emite entre cada 16ms y 200ms
  // durante la reproducción (documentado en su propio código) — sobra para
  // el "al menos una vez por segundo" que pide el criterio de aceptación.
  // No emite en pausa/detenido, pero eso no hace falta: la pantalla reinicia
  // su propio valor mostrado a 0 al ver el estado "detenido" (ver
  // PracticaPalabraScreen), sin depender de que este stream también lo haga.
  @override
  Stream<Duration> get posicion => _reproductor.positionStream;

  @override
  Stream<Duration?> get duracion => _reproductor.durationStream;

  void _alCambiarEstado(PlayerState estadoNativo) {
    if (_reiniciando) return;
    if (estadoNativo.processingState == ProcessingState.completed) {
      unawaited(_reiniciar(detenerDelTodo: false));
      return;
    }
    switch (estadoNativo.processingState) {
      case ProcessingState.loading:
      case ProcessingState.buffering:
        _controlador.add(EstadoAudio.cargando);
      case ProcessingState.ready:
        _controlador.add(
          estadoNativo.playing ? EstadoAudio.reproduciendo : EstadoAudio.pausado,
        );
      case ProcessingState.idle:
      case ProcessingState.completed:
        break;
    }
  }

  Future<void> _reiniciar({required bool detenerDelTodo}) async {
    _reiniciando = true;
    try {
      if (detenerDelTodo) {
        await _reproductor.stop();
      } else {
        await _reproductor.pause();
      }
      await _reproductor.seek(Duration.zero);
      _controlador.add(EstadoAudio.detenido);
    } finally {
      _reiniciando = false;
    }
  }

  @override
  Future<void> reproducir(String url) async {
    _controlador.add(EstadoAudio.cargando);
    try {
      // RNF-03: siempre se reproduce desde el archivo local, nunca
      // directamente de la url — obtenerRutaLocal ya decide por su cuenta
      // si hace falta descargarlo primero o si puede regresar de inmediato
      // una copia que ya estaba en el dispositivo.
      final rutaLocal = await _cache.obtenerRutaLocal(url);
      await _reproductor.setFilePath(rutaLocal);
      await _reproductor.play();
    } catch (_) {
      // Sin esto, un fallo aquí (audio inexistente, red caída) deja el
      // estado atorado en "cargando" — el ícono girando para siempre en vez
      // de volver a un estado desde el que se pueda reintentar.
      _controlador.add(EstadoAudio.detenido);
      rethrow;
    }
  }

  @override
  Future<void> pausar() => _reproductor.pause();

  @override
  Future<void> reanudar() => _reproductor.play();

  @override
  Future<void> detener() => _reiniciar(detenerDelTodo: true);

  @override
  Future<void> retroceder() => _saltar(-_saltoSegundos);

  @override
  Future<void> adelantar() => _saltar(_saltoSegundos);

  Future<void> _saltar(Duration delta) => _reproductor.seek(
    posicionTrasSalto(
      actual: _reproductor.position,
      delta: delta,
      duracion: _reproductor.duration,
    ),
  );

  @override
  Future<void> dispose() async {
    await _suscripcion.cancel();
    await _controlador.close();
    await _reproductor.dispose();
  }
}

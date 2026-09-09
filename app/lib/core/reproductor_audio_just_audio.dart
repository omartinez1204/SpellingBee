import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'reproductor_audio.dart';

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
class ReproductorAudioJustAudio implements ReproductorAudio {
  ReproductorAudioJustAudio() {
    _suscripcion = _reproductor.playerStateStream.listen(_alCambiarEstado);
  }

  final AudioPlayer _reproductor = AudioPlayer();
  final _controlador = StreamController<EstadoAudio>.broadcast();
  late final StreamSubscription<PlayerState> _suscripcion;

  // Mientras se ejecuta _reiniciar(), se ignoran los eventos intermedios que
  // el propio stop()/pause()+seek() dispara (p. ej. un "pausado" transitorio
  // entre el pause y el seek) — el único estado válido al terminar es
  // "detenido", emitido a mano al final.
  bool _reiniciando = false;

  @override
  Stream<EstadoAudio> get estado => _controlador.stream;

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
      await _reproductor.setUrl(url);
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
  Future<void> dispose() async {
    await _suscripcion.cancel();
    await _controlador.close();
    await _reproductor.dispose();
  }
}

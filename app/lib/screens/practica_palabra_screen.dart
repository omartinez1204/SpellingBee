import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/detalle_palabra.dart';
import '../core/palabras_service.dart';
import '../core/reproductor_audio.dart';
import '../core/reproductor_audio_just_audio.dart';

/// RF-07 (T-026) + RF-12/13/14/15/16/17 (T-030/T-031): pantalla de práctica
/// de UNA palabra. Muestra de inmediato y de forma visible solo la palabra
/// en inglés y un ícono de audio; significado y oración de ejemplo quedan
/// ocultos al inicio, disponibles mediante dos botones de pista que el
/// alumno activa voluntariamente. El ícono de audio reproduce/pausa/reanuda
/// (RF-12/13); retroceder/adelantar 5s (RF-14/15) y detener (RF-16)
/// aparecen mientras hay algo sobre lo que actuar (reproduciendo o
/// pausada). No hay límite de reproducciones (RF-17): terminar o detener
/// deja la pista lista para volver a tocarse desde el inicio.
///
/// [DISEÑO PROPUESTO POR EL EQUIPO, NO INSTRUCCIÓN LITERAL DEL CLIENTE — ver
/// ERS §8.2 y docs/backlog.md "Bloqueadores": confirmar con el cliente
/// (profesor Omar) el copy/UX definitivo de estos botones antes de darlo
/// por cerrado.]
///
/// La barra de progreso + texto mm:ss (RF-18) es T-032 — no está aquí
/// todavía.
class PracticaPalabraScreen extends StatefulWidget {
  const PracticaPalabraScreen({
    super.key,
    required this.idPalabra,
    this.palabrasService,
    this.reproductor,
  });

  final int idPalabra;
  final PalabrasService? palabrasService;

  /// Inyectable solo para pruebas — mismo motivo que palabrasService: sin
  /// esto, la pantalla siempre construiría un ReproductorAudioJustAudio real,
  /// que necesita un canal de plataforma de audio que no existe bajo
  /// `flutter test`.
  final ReproductorAudio? reproductor;

  @override
  State<PracticaPalabraScreen> createState() => _PracticaPalabraScreenState();
}

class _PracticaPalabraScreenState extends State<PracticaPalabraScreen> {
  late final PalabrasService _palabrasService;
  late final ReproductorAudio _reproductor;
  late final StreamSubscription<EstadoAudio> _suscripcionAudio;
  late final Future<DetallePalabra> _futuraPalabra;

  bool _significadoVisible = false;
  bool _oracionVisible = false;
  EstadoAudio _estadoAudio = EstadoAudio.detenido;

  @override
  void initState() {
    super.initState();
    _palabrasService = widget.palabrasService ?? PalabrasService();
    _reproductor = widget.reproductor ?? ReproductorAudioJustAudio();
    _futuraPalabra = _palabrasService.obtenerDetalle(widget.idPalabra);
    _suscripcionAudio = _reproductor.estado.listen((estado) {
      if (mounted) setState(() => _estadoAudio = estado);
    });
  }

  @override
  void dispose() {
    _suscripcionAudio.cancel();
    unawaited(_reproductor.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practicar palabra')),
      body: SafeArea(
        child: FutureBuilder<DetallePalabra>(
          future: _futuraPalabra,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final mensaje = error is ApiException
                  ? error.message
                  : 'No se pudo cargar la palabra.';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(mensaje, textAlign: TextAlign.center),
                ),
              );
            }

            final palabra = snapshot.data!;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        palabra.texto,
                        style: Theme.of(context).textTheme.displaySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_sePuedeSaltar) ...[
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.replay_5),
                              tooltip: 'Retroceder 5 segundos',
                              onPressed: () =>
                                  _saltar(_reproductor.retroceder),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _botonReproducir(palabra.urlAudio),
                          if (_sePuedeSaltar) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.forward_5),
                              tooltip: 'Adelantar 5 segundos',
                              onPressed: () =>
                                  _saltar(_reproductor.adelantar),
                            ),
                          ],
                          if (_sePuedeSaltar) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              iconSize: 36,
                              icon: const Icon(Icons.stop),
                              tooltip: 'Detener',
                              onPressed: _detener,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 32),
                      _BotonPista(
                        etiqueta: 'Ver significado',
                        contenido: palabra.significadoEs,
                        contenidoVacio:
                            'Esta palabra todavía no tiene significado capturado.',
                        visible: _significadoVisible,
                        onPresionar: () =>
                            setState(() => _significadoVisible = true),
                      ),
                      const SizedBox(height: 16),
                      _BotonPista(
                        etiqueta: 'Ver ejemplo',
                        contenido: palabra.oracionEjemplo,
                        contenidoVacio:
                            'Esta palabra todavía no tiene oración de ejemplo capturada.',
                        visible: _oracionVisible,
                        onPresionar: () =>
                            setState(() => _oracionVisible = true),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // RNF-03 sugiere feedback inmediato de que algo está pasando mientras
  // carga (debería tardar <2s); un ícono fijo sin cambios ahí se siente
  // como que no reaccionó al toque.
  Widget _botonReproducir(String? urlRelativa) {
    if (_estadoAudio == EstadoAudio.cargando) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    final IconData icono;
    final String tooltip;
    switch (_estadoAudio) {
      case EstadoAudio.reproduciendo:
        icono = Icons.pause;
        tooltip = 'Pausar';
      case EstadoAudio.pausado:
        icono = Icons.play_arrow;
        tooltip = 'Reanudar';
      case EstadoAudio.detenido:
      case EstadoAudio.cargando:
        icono = Icons.volume_up;
        tooltip = 'Reproducir pronunciación';
    }
    return IconButton(
      iconSize: 48,
      icon: Icon(icono),
      tooltip: tooltip,
      onPressed: () => _alPresionarReproducir(urlRelativa),
    );
  }

  Future<void> _alPresionarReproducir(String? urlRelativa) async {
    if (urlRelativa == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta palabra todavía no tiene audio disponible.'),
        ),
      );
      return;
    }
    try {
      switch (_estadoAudio) {
        case EstadoAudio.detenido:
          await _reproductor.reproducir(
            '${_palabrasService.baseUrl}$urlRelativa',
          );
        case EstadoAudio.reproduciendo:
          await _reproductor.pausar();
        case EstadoAudio.pausado:
          await _reproductor.reanudar();
        case EstadoAudio.cargando:
          break;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No se pudo reproducir el audio.')));
    }
  }

  // RF-16. Si detener() llegara a fallar, el peor caso es que el botón de
  // detener se quede visible — no hay más que mostrarle al alumno por un
  // control que ni pretende dar retroalimentación de error en el ERS.
  Future<void> _detener() async {
    try {
      await _reproductor.detener();
    } catch (_) {
      // Ver comentario arriba.
    }
  }

  // RF-14/RF-15: "mientras se reproduce o está pausada" — no hay nada que
  // retroceder/adelantar en "detenido" (no hay pista cargada) ni en
  // "cargando" (posición/duración todavía no estables). Mismo criterio que
  // ya usa el botón de detener.
  bool get _sePuedeSaltar =>
      _estadoAudio == EstadoAudio.reproduciendo ||
      _estadoAudio == EstadoAudio.pausado;

  // retroceder()/adelantar() no tienen por qué fallar en la práctica (a
  // diferencia de reproducir(), no involucran cargar nada nuevo); si de
  // cualquier forma fallaran, no hay una retroalimentación mejor que
  // mostrarle al alumno por un control que el ERS no especifica con error.
  Future<void> _saltar(Future<void> Function() accion) async {
    try {
      await accion();
    } catch (_) {
      // Ver comentario arriba.
    }
  }
}

/// Antes de presionarse: el botón de pista. Después: el contenido revelado,
/// sin forma de volver a ocultarlo (es una pista, no un interruptor).
class _BotonPista extends StatelessWidget {
  const _BotonPista({
    required this.etiqueta,
    required this.contenido,
    required this.contenidoVacio,
    required this.visible,
    required this.onPresionar,
  });

  final String etiqueta;
  final String? contenido;
  final String contenidoVacio;
  final bool visible;
  final VoidCallback onPresionar;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(onPressed: onPresionar, child: Text(etiqueta)),
      );
    }

    final tieneContenido = contenido != null && contenido!.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tieneContenido ? contenido! : contenidoVacio,
        textAlign: TextAlign.center,
        style: tieneContenido
            ? null
            : TextStyle(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.outline,
              ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/detalle_palabra.dart';
import '../core/formato_tiempo.dart';
import '../core/mensaje_motivacional.dart';
import '../core/palabras_service.dart';
import '../core/practica_service.dart';
import '../core/reproductor_audio.dart';
import '../core/reproductor_audio_just_audio.dart';

/// RF-07 (T-026) + RF-12 a RF-18 (T-030/T-031/T-032) + RF-19 a RF-22
/// (T-040/T-041/T-042): pantalla de práctica de UNA palabra. Muestra de
/// inmediato y de forma visible solo la palabra en inglés y un ícono de
/// audio; significado y oración de ejemplo quedan ocultos al inicio,
/// disponibles mediante dos botones de pista que el alumno activa
/// voluntariamente. El ícono de audio reproduce/pausa/reanuda (RF-12/13);
/// retroceder/adelantar 5s (RF-14/15), detener (RF-16) y la barra de
/// progreso + texto mm:ss (RF-18) aparecen mientras hay algo sobre lo que
/// actuar (reproduciendo o pausada). No hay límite de reproducciones
/// (RF-17): terminar o detener deja la pista lista para volver a tocarse
/// desde el inicio. Debajo, un cronómetro único para toda la práctica de la
/// palabra permanece en 00:00 hasta que el alumno presiona "Iniciar"; a
/// partir de ahí corre solo, actualizándose cada segundo, hasta que
/// presiona "Terminé", que lo detiene y fija el tiempo final (RF-21) y
/// dispara la consulta a GET /practica/mejor-tiempo para mostrar un mensaje
/// motivacional (RF-22): bienvenida en el primer intento, o mejoró/igualó/
/// no superó comparado con la marca previa. Guardar el registro en el
/// backend (T-045) queda fuera de esta pantalla todavía.
///
/// [DISEÑO PROPUESTO POR EL EQUIPO, NO INSTRUCCIÓN LITERAL DEL CLIENTE — ver
/// ERS §8.2 y docs/backlog.md "Bloqueadores": confirmar con el cliente
/// (profesor Omar) el copy/UX definitivo de estos botones antes de darlo
/// por cerrado.]
class PracticaPalabraScreen extends StatefulWidget {
  const PracticaPalabraScreen({
    super.key,
    required this.idPalabra,
    required this.token,
    this.palabrasService,
    this.reproductor,
    this.ahora,
    this.practicaService,
  });

  final int idPalabra;
  final PalabrasService? palabrasService;

  /// RF-22 (T-042): GET /practica/mejor-tiempo/:id necesita sesión — el
  /// backend responde sobre el alumno del propio JWT, no hay id que pasar
  /// aparte. Quien navega a esta pantalla siempre tiene sesión iniciada
  /// (HomeScreen ya exige authController.sesion no nulo para existir), así
  /// que se pide el token directo — no todo AuthController — igual de
  /// angosto que palabrasService/reproductor: esta pantalla no necesita
  /// nada más de la sesión (ni rol, ni cerrarla, etc).
  final String token;

  /// Inyectable solo para pruebas — mismo motivo que palabrasService: sin
  /// esto, la pantalla siempre construiría un ReproductorAudioJustAudio real,
  /// que necesita un canal de plataforma de audio que no existe bajo
  /// `flutter test`.
  final ReproductorAudio? reproductor;

  /// Inyectable solo para pruebas (T-040): DateTime.now() no avanza con
  /// tester.pump(duration) — a diferencia de los Timer, que sí obedecen el
  /// reloj falso de las pruebas de widgets — así que sin este seam no habría
  /// forma determinista de probar RF-20/RNF-04 bajo `flutter test`.
  final DateTime Function()? ahora;

  /// Inyectable solo para pruebas (T-042) — mismo motivo que
  /// palabrasService.
  final PracticaService? practicaService;

  @override
  State<PracticaPalabraScreen> createState() => _PracticaPalabraScreenState();
}

class _PracticaPalabraScreenState extends State<PracticaPalabraScreen> {
  late final PalabrasService _palabrasService;
  late final ReproductorAudio _reproductor;
  late final DateTime Function() _ahora;
  late final PracticaService _practicaService;
  late final StreamSubscription<EstadoAudio> _suscripcionAudio;
  late final StreamSubscription<Duration> _suscripcionPosicion;
  late final StreamSubscription<Duration?> _suscripcionDuracion;
  late final Future<DetallePalabra> _futuraPalabra;

  bool _significadoVisible = false;
  bool _oracionVisible = false;
  EstadoAudio _estadoAudio = EstadoAudio.detenido;
  Duration _posicion = Duration.zero;
  Duration? _duracion;

  // RF-19/RF-20/RNF-04: _inicioCronometro es la única fuente de verdad (no
  // un contador de segundos incrementado por tick) — cada tick recalcula
  // contra el reloj real, así que un tick que llega tarde (frame perdido,
  // GC) nunca se acumula como desviación: el peor caso es que el valor en
  // pantalla se quede fijo un instante extra, nunca que quede adelantado o
  // atrasado respecto al tiempo real transcurrido.
  DateTime? _inicioCronometro;
  Duration _tiempoTranscurrido = Duration.zero;
  Timer? _tickerCronometro;
  bool _practicaTerminada = false;
  String? _mensajeMotivacional;

  bool get _cronometroIniciado => _inicioCronometro != null;

  @override
  void initState() {
    super.initState();
    _palabrasService = widget.palabrasService ?? PalabrasService();
    _reproductor = widget.reproductor ?? ReproductorAudioJustAudio();
    _ahora = widget.ahora ?? DateTime.now;
    _practicaService = widget.practicaService ?? PracticaService();
    _futuraPalabra = _palabrasService.obtenerDetalle(widget.idPalabra);
    _suscripcionAudio = _reproductor.estado.listen((estado) {
      if (!mounted) return;
      setState(() {
        _estadoAudio = estado;
        // RF-16/RF-17: al detener (manual o por fin natural) el indicador
        // debe volver al inicio — sin esto, se quedaría mostrando el
        // último valor conocido en vez de 0:00. No depende de que
        // posicion también emita un cero justo en ese momento.
        if (estado == EstadoAudio.detenido) _posicion = Duration.zero;
      });
    });
    _suscripcionPosicion = _reproductor.posicion.listen((posicion) {
      if (mounted) setState(() => _posicion = posicion);
    });
    _suscripcionDuracion = _reproductor.duracion.listen((duracion) {
      if (mounted) setState(() => _duracion = duracion);
    });
  }

  // RF-19: acción explícita y única — "es el alumno quien decide cuándo
  // empezar". El guard evita que un doble toque (o cualquier otra llamada
  // futura) reinicie un cronómetro que ya corre.
  void _iniciarCronometro() {
    if (_cronometroIniciado) return;
    setState(() {
      _inicioCronometro = _ahora();
      _tiempoTranscurrido = Duration.zero;
    });
    _tickerCronometro = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _tiempoTranscurrido = _ahora().difference(_inicioCronometro!));
    });
  }

  // RF-21. Deliberadamente NO vuelve a calcular _ahora().difference(...) —
  // el criterio de aceptación exige que "el tiempo final registrado
  // coincide con el mostrado en pantalla al momento de marcar Terminé", y
  // recalcular podría adelantar el valor uno o dos décimos de segundo más
  // allá de lo que el alumno alcanzó a ver en el último tick. Cancelar el
  // ticker sin tocar _tiempoTranscurrido deja fijo exactamente ese último
  // valor mostrado.
  Future<void> _terminarPractica() async {
    if (!_cronometroIniciado || _practicaTerminada) return;
    _tickerCronometro?.cancel();
    setState(() => _practicaTerminada = true);

    // RF-22: la comparación es "best effort" — el tiempo ya quedó fijo y
    // registrado en pantalla (RF-21) sin importar si esto falla; solo el
    // mensaje motivacional depende de la red.
    try {
      final mejorPrevio = await _practicaService.obtenerMejorTiempoSegundos(
        widget.idPalabra,
        widget.token,
      );
      if (!mounted) return;
      setState(() {
        _mensajeMotivacional = construirMensajeMotivacional(
          actualSegundos: _tiempoTranscurrido.inSeconds,
          mejorPrevioSegundos: mejorPrevio,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar tu comparación con tu mejor tiempo.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _suscripcionAudio.cancel();
    _suscripcionPosicion.cancel();
    _suscripcionDuracion.cancel();
    _tickerCronometro?.cancel();
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
                      if (_sePuedeSaltar) ...[
                        _BarraDeProgreso(posicion: _posicion, duracion: _duracion),
                        const SizedBox(height: 24),
                      ],
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
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 16),
                      _SeccionDeletreo(palabraTexto: palabra.texto),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      _SeccionCronometro(
                        iniciado: _cronometroIniciado,
                        terminado: _practicaTerminada,
                        tiempoTranscurrido: _tiempoTranscurrido,
                        mensajeMotivacional: _mensajeMotivacional,
                        onIniciar: _iniciarCronometro,
                        onTerminar: _terminarPractica,
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

/// RF-19/RF-20 (T-040) + RF-21 (T-041): cronómetro único y combinado para
/// toda la práctica de la palabra (pronunciación, deletreo y oración
/// juntos) — no uno por sub-actividad, así que vive aquí, al nivel de la
/// pantalla completa, y no dentro de ningún widget de una sub-actividad en
/// particular. Antes de iniciar se ve fijo en 00:00 (no un campo vacío ni
/// oculto); el botón "Iniciar" desaparece una vez iniciado porque es una
/// acción única, no reiniciable (RF-19: "es el alumno quien decide cuándo
/// empezar"). "Terminé" solo tiene sentido mientras corre; al presionarlo
/// desaparece también — no hay forma de "reabrir" el cronómetro de esta
/// pantalla (eso, si hiciera falta, sería una palabra nueva, no la misma
/// práctica).
class _SeccionCronometro extends StatelessWidget {
  const _SeccionCronometro({
    required this.iniciado,
    required this.terminado,
    required this.tiempoTranscurrido,
    required this.mensajeMotivacional,
    required this.onIniciar,
    required this.onTerminar,
  });

  final bool iniciado;
  final bool terminado;
  final Duration tiempoTranscurrido;

  /// RF-22 (T-042). null mientras no se ha terminado, o mientras la
  /// consulta al backend sigue en vuelo — no hay nada que mostrar todavía,
  /// no es un estado de error.
  final String? mensajeMotivacional;
  final VoidCallback onIniciar;
  final VoidCallback onTerminar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          formatearTiempo(tiempoTranscurrido),
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 12),
        if (!iniciado)
          FilledButton.icon(
            onPressed: onIniciar,
            // No Icons.play_arrow: ese ya lo usa "reanudar" del reproductor
            // de audio (RF-13), visible al mismo tiempo que este botón.
            icon: const Icon(Icons.timer),
            label: const Text('Iniciar'),
          )
        else if (!terminado)
          FilledButton.icon(
            onPressed: onTerminar,
            icon: const Icon(Icons.check),
            label: const Text('Terminé'),
          ),
        if (mensajeMotivacional != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              mensajeMotivacional!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// RF-18. Barra de solo lectura (no de arrastrar-para-buscar: eso no lo pide
/// el ERS — retroceder/adelantar ya cubren el avance/retroceso, RF-14/15) +
/// texto "mm:ss / mm:ss" tal como lo da el ejemplo del ERS ("00:03 / 00:12").
class _BarraDeProgreso extends StatelessWidget {
  const _BarraDeProgreso({required this.posicion, required this.duracion});

  final Duration posicion;
  final Duration? duracion;

  @override
  Widget build(BuildContext context) {
    final duracionConocida = duracion != null && duracion!.inMilliseconds > 0;
    final valor = duracionConocida
        ? (posicion.inMilliseconds / duracion!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: valor, minHeight: 6),
        ),
        const SizedBox(height: 4),
        Text(
          '${formatearTiempo(posicion)} / '
          '${duracionConocida ? formatearTiempo(duracion!) : '--:--'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
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

/// RF-25 (T-043): bloques de letras estilo Duolingo. Cada ficha recuerda la
/// posición ORIGINAL de su letra dentro de `palabraTexto` (no solo el
/// carácter) para poder tener varias fichas con la misma letra sin
/// confundirlas entre sí (p. ej. "business" trae tres fichas "s" distintas).
/// Verificar consiste en unir las letras en el orden colocado y compararlo
/// contra la palabra original: al ser fichas con las letras EXACTAS de la
/// palabra (sin distractores), esa comparación de texto nunca necesita
/// normalizar mayúsculas/minúsculas ni espacios, tal como aclara el propio
/// criterio de RF-25. Interacción por TOQUE, no arrastre: el diseño técnico
/// acepta "fichas arrastrables/tocables" como equivalentes, y tocar es más
/// simple de implementar y de probar de forma determinista que un gesto de
/// arrastre.
///
/// Independiente del cronómetro (RF-19/T-040): igual que el reproductor de
/// audio y las pistas, ya utilizables antes de presionar "Iniciar" desde
/// T-030, este bloque no revisa `_cronometroIniciado` — el cronómetro solo
/// mide el tiempo total, no impone una secuencia obligatoria de pasos.
class _SeccionDeletreo extends StatefulWidget {
  const _SeccionDeletreo({required this.palabraTexto});

  final String palabraTexto;

  @override
  State<_SeccionDeletreo> createState() => _SeccionDeletreoState();
}

class _SeccionDeletreoState extends State<_SeccionDeletreo> {
  late final List<String> _letras;
  late List<int> _disponibles;
  final List<int> _colocados = [];

  /// null: todavía no se ha verificado (o la disposición cambió desde la
  /// última verificación). true/false: resultado de la última verificación.
  bool? _esCorrecto;

  @override
  void initState() {
    super.initState();
    _letras = widget.palabraTexto.split('');
    _disponibles = List.generate(_letras.length, (indice) => indice)
      ..shuffle();
  }

  bool get _completo => _colocados.length == _letras.length;

  void _colocar(int indice) {
    setState(() {
      _disponibles.remove(indice);
      _colocados.add(indice);
      _esCorrecto = null;
    });
  }

  // Permite corregir un error de toque sin tener que reiniciar todo el
  // ejercicio — no lo exige RF-25 literalmente, pero sin esto una sola ficha
  // mal colocada sería irrecuperable.
  void _quitar(int indice) {
    setState(() {
      _colocados.remove(indice);
      _disponibles.add(indice);
      _esCorrecto = null;
    });
  }

  // Compara TEXTO, no identidad de fichas: con letras repetidas (p. ej. las
  // tres "s" de "business"), cuál ficha física ocupó cuál posición no
  // importa — lo único que RF-25 pide comparar es si lo armado deletrea la
  // palabra, y dos fichas con la misma letra son intercambiables entre sí.
  void _verificar() {
    if (!_completo) return;
    final formada = _colocados.map((indice) => _letras[indice]).join();
    setState(() => _esCorrecto = formada == widget.palabraTexto);
  }

  @override
  Widget build(BuildContext context) {
    // RF-25: "el sistema lo indica sin bloquear el avance" — solo se
    // congelan las fichas cuando el resultado ya fue correcto; si fue
    // incorrecto, el alumno sigue libre de ajustar y volver a verificar.
    final bloqueado = _esCorrecto == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ordena las letras para deletrear la palabra',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _letras.length; i++)
              if (i < _colocados.length)
                _FichaLetra(
                  key: ValueKey('ficha-colocada-${_colocados[i]}'),
                  letra: _letras[_colocados[i]],
                  onPresionar: bloqueado ? null : () => _quitar(_colocados[i]),
                )
              else
                const _FichaVacia(),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final indice in _disponibles)
              _FichaLetra(
                key: ValueKey('ficha-disponible-$indice'),
                letra: _letras[indice],
                onPresionar: () => _colocar(indice),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _completo && !bloqueado ? _verificar : null,
          child: const Text('Verificar orden'),
        ),
        if (_esCorrecto != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _esCorrecto!
                  ? Colors.green.shade100
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _esCorrecto!
                  ? '¡Correcto! Ese es el orden de las letras.'
                  : 'Todavía no es el orden correcto — ajusta las fichas e '
                        'inténtalo de nuevo.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _FichaLetra extends StatelessWidget {
  const _FichaLetra({super.key, required this.letra, required this.onPresionar});

  final String letra;
  final VoidCallback? onPresionar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPresionar,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(letra, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
      ),
    );
  }
}

/// Espacio reservado para una letra que el alumno todavía no ha colocado —
/// deja ver cuántas fichas faltan sin revelar cuáles son.
class _FichaVacia extends StatelessWidget {
  const _FichaVacia();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

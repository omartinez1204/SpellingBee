import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/detalle_palabra.dart';
import '../core/palabras_service.dart';

/// RF-07 (T-026): pantalla de práctica de UNA palabra. Muestra de inmediato
/// y de forma visible solo la palabra en inglés y un ícono de audio;
/// significado y oración de ejemplo quedan ocultos al inicio, disponibles
/// mediante dos botones de pista que el alumno activa voluntariamente.
///
/// [DISEÑO PROPUESTO POR EL EQUIPO, NO INSTRUCCIÓN LITERAL DEL CLIENTE — ver
/// ERS §8.2 y docs/backlog.md "Bloqueadores": confirmar con el cliente
/// (profesor Omar) el copy/UX definitivo de estos botones antes de darlo
/// por cerrado.]
///
/// La reproducción real de audio (RF-12) es Fase 3 (T-030) — aquí el ícono
/// es solo un indicador visual, todavía no reproduce nada.
class PracticaPalabraScreen extends StatefulWidget {
  const PracticaPalabraScreen({
    super.key,
    required this.idPalabra,
    this.palabrasService,
  });

  final int idPalabra;
  final PalabrasService? palabrasService;

  @override
  State<PracticaPalabraScreen> createState() => _PracticaPalabraScreenState();
}

class _PracticaPalabraScreenState extends State<PracticaPalabraScreen> {
  late final PalabrasService _palabrasService;
  late final Future<DetallePalabra> _futuraPalabra;

  bool _significadoVisible = false;
  bool _oracionVisible = false;

  @override
  void initState() {
    super.initState();
    _palabrasService = widget.palabrasService ?? PalabrasService();
    _futuraPalabra = _palabrasService.obtenerDetalle(widget.idPalabra);
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
                      IconButton(
                        iconSize: 48,
                        icon: const Icon(Icons.volume_up),
                        tooltip: 'Reproducir pronunciación',
                        onPressed: () => _mostrarAudioProximamente(context),
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

  void _mostrarAudioProximamente(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('La reproducción de audio llega en una fase posterior.'),
      ),
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

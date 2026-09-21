import 'package:flutter/material.dart';

import '../core/cola_practica_archivo.dart';
import '../core/detalle_palabra.dart';
import '../core/niveles_controller.dart';
import '../core/paquete_nivel.dart';
import '../core/sincronizador_practica.dart';
import '../widgets/indicador_sincronizacion.dart';
import 'practica_palabra_screen.dart';

/// RF-31/RF-32 (T-061): punto de entrada de práctica del alumno — todavía
/// sin uno propio en el backlog (ver el comentario de HomeScreen). Lista
/// los 3 niveles (RF-05); cada uno se puede descargar (paquete completo +
/// audios, T-060) para practicar después sin conexión. Una vez descargado,
/// se despliega la lista de sus palabras — tocar una abre la práctica
/// (T-026) usando SOLO el contenido ya guardado en el dispositivo, sin
/// ninguna llamada de red para cargar la palabra ni su audio.
class NivelesScreen extends StatefulWidget {
  const NivelesScreen({
    super.key,
    required this.token,
    this.controller,
    this.sincronizador,
  });

  final String token;

  /// Inyectable solo para pruebas — mismo motivo que en el resto de la app:
  /// sin esto, la pantalla siempre construiría un NivelesController con
  /// servicios/almacén/caché reales.
  final NivelesController? controller;

  /// RF-33 (T-062): compartido con la sesión completa del alumno (ver
  /// HomeScreen, dueño real del ciclo de vida de este objeto) — esta
  /// pantalla solo lo recibe y lo reenvía a PracticaPalabraScreen al abrir
  /// una palabra; nunca lo crea con iniciar() ni lo cierra con dispose(),
  /// justo como palabraDescargada/token de más abajo. null (inyectable solo
  /// para pruebas, o cualquier navegación futura sin HomeScreen de por
  /// medio) hace que esta pantalla arme uno propio, sin arrancarlo.
  final SincronizadorPractica? sincronizador;

  @override
  State<NivelesScreen> createState() => _NivelesScreenState();
}

/// T-070 (RNF-12): cuántas palabras de un nivel descargado se pintan de una
/// vez. El paquete ya está en el dispositivo (no hay red de por medio), pero
/// un nivel puede crecer más allá de 50 palabras y construir todos sus
/// ListTile a la vez es justo lo que RNF-12 pide evitar: se pintan por lotes
/// y "Mostrar más" agrega el siguiente.
const _palabrasPorLote = 50;

class _NivelesScreenState extends State<NivelesScreen> {
  late final NivelesController _controller;
  late final SincronizadorPractica _sincronizador;

  /// Palabras visibles por nivel. Vive aquí (no en la tarjeta) para que
  /// sobreviva a que la tarjeta salga de pantalla al hacer scroll.
  final Map<int, int> _palabrasVisibles = {};

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? NivelesController(token: widget.token);
    _sincronizador =
        widget.sincronizador ??
        SincronizadorPractica(
          cola: ColaPracticaArchivo(),
          token: widget.token,
        );
    _controller.cargarInicial();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practicar'),
        actions: [IndicadorSincronizacion(sincronizador: _sincronizador)],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_controller.cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_controller.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _controller.cargarInicial,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _controller.niveles.length,
      itemBuilder: (context, index) {
        final nivel = _controller.niveles[index];
        final visibles = _palabrasVisibles[nivel.id] ?? _palabrasPorLote;
        return _TarjetaNivel(
          idNivel: nivel.id,
          nombre: nivel.nombre,
          descargado: _controller.estaDescargado(nivel.id),
          descargando: _controller.estaDescargando(nivel.id),
          error: _controller.errorDescarga(nivel.id),
          paquete: _controller.paqueteLocal(nivel.id),
          palabrasVisibles: visibles,
          onDescargar: () => _controller.descargar(nivel.id),
          onAbrirPalabra: _abrirPractica,
          onMostrarMas: () => setState(
            () => _palabrasVisibles[nivel.id] = visibles + _palabrasPorLote,
          ),
        );
      },
    );
  }

  void _abrirPractica(DetallePalabra palabra) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticaPalabraScreen(
          idPalabra: palabra.id,
          token: widget.token,
          palabraDescargada: palabra,
          sincronizador: _sincronizador,
        ),
      ),
    );
  }
}

class _TarjetaNivel extends StatelessWidget {
  const _TarjetaNivel({
    required this.idNivel,
    required this.nombre,
    required this.descargado,
    required this.descargando,
    required this.error,
    required this.paquete,
    required this.palabrasVisibles,
    required this.onDescargar,
    required this.onAbrirPalabra,
    required this.onMostrarMas,
  });

  final int idNivel;
  final String nombre;
  final bool descargado;
  final bool descargando;
  final String? error;
  final PaqueteNivel? paquete;
  final int palabrasVisibles;
  final VoidCallback onDescargar;
  final ValueChanged<DetallePalabra> onAbrirPalabra;
  final VoidCallback onMostrarMas;

  String _textoMostrarMas(int totalPalabras) {
    final restantes = totalPalabras - palabrasVisibles;
    return 'Mostrar más ($restantes ${restantes == 1 ? 'restante' : 'restantes'})';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nombre,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (descargado)
                  const Chip(
                    avatar: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.green,
                    ),
                    label: Text('Descargado'),
                  ),
              ],
            ),
            if (!descargado) ...[
              const SizedBox(height: 8),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                key: Key('descargar-nivel-$idNivel'),
                onPressed: descargando ? null : onDescargar,
                icon: descargando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  descargando
                      ? 'Descargando…'
                      : 'Descargar para practicar sin conexión',
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              if (paquete!.palabras.isEmpty)
                const Text(
                  'Este nivel todavía no tiene palabras disponibles para descargar.',
                )
              else ...[
                ...paquete!.palabras
                    .take(palabrasVisibles)
                    .map(
                      (palabra) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(palabra.texto),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onAbrirPalabra(palabra),
                      ),
                    ),
                if (paquete!.palabras.length > palabrasVisibles)
                  TextButton(
                    key: Key('mostrar-mas-palabras-$idNivel'),
                    onPressed: onMostrarMas,
                    child: Text(_textoMostrarMas(paquete!.palabras.length)),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/carreras.dart';
import '../core/detalle_alumno_controller.dart';
import '../core/formato_tiempo.dart';
import '../core/intento_practica.dart';

/// RF-29 (T-053, CU-03 paso 4): detalle de un alumno — palabra, tiempo y
/// oración de cada intento registrado, paginado (RNF-12) con scroll infinito
/// (mismo mecanismo que AdminCatalogoScreen, T-027), con los mismos filtros
/// combinables de nivel/carrera/semestre que la lista (T-052, RF-30).
class DetalleAlumnoScreen extends StatefulWidget {
  const DetalleAlumnoScreen({
    super.key,
    required this.token,
    required this.idAlumno,
    required this.nombreAlumno,
    this.controller,
  });

  final String token;
  final int idAlumno;

  /// Ya lo tiene quien navega aquí (viene de la fila de la lista) — pedirlo
  /// de nuevo al backend solo para mostrar el título sería una llamada de
  /// más.
  final String nombreAlumno;

  /// Inyectable solo para pruebas — mismo motivo que en el resto de la app:
  /// sin esto, la pantalla siempre construiría un DetalleAlumnoController con
  /// un ApiClient real.
  final DetalleAlumnoController? controller;

  @override
  State<DetalleAlumnoScreen> createState() => _DetalleAlumnoScreenState();
}

class _DetalleAlumnoScreenState extends State<DetalleAlumnoScreen> {
  late final DetalleAlumnoController _controller;
  final _scrollController = ScrollController();

  // Selección PENDIENTE de los filtros — no se manda al backend hasta
  // presionar "Aplicar filtros" (RF-30), mismo criterio que
  // SeguimientoAlumnosScreen.
  int? _nivelSeleccionado;
  String? _carreraSeleccionada;
  int? _semestreSeleccionado;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        DetalleAlumnoController(token: widget.token, idAlumno: widget.idAlumno);
    _controller.cargarInicial();
    _scrollController.addListener(_alLlegarAlFinal);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _alLlegarAlFinal() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _controller.cargarMas();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombreAlumno)),
      // Todo el cuerpo va DENTRO del mismo AnimatedBuilder — el panel de
      // filtros depende de _controller.niveles, que llega vacío hasta que
      // cargarInicial() resuelve; dejarlo fuera de este AnimatedBuilder
      // (como pasó una vez en SeguimientoAlumnosScreen, T-053) congelaría el
      // dropdown de nivel sin opciones para siempre.
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Column(
          children: [
            _panelFiltros(),
            const Divider(height: 1),
            Expanded(child: _cuerpoLista()),
          ],
        ),
      ),
    );
  }

  Widget _panelFiltros() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          DropdownButtonFormField<int?>(
            key: const Key('filtro-nivel'),
            initialValue: _nivelSeleccionado,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nivel'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              ..._controller.niveles.map(
                (nivel) => DropdownMenuItem(
                  value: nivel.id,
                  child: Text(nivel.nombre),
                ),
              ),
            ],
            onChanged: (valor) => setState(() => _nivelSeleccionado = valor),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const Key('filtro-carrera'),
            initialValue: _carreraSeleccionada,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Carrera'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todas')),
              ...carreras.map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (valor) =>
                setState(() => _carreraSeleccionada = valor),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            key: const Key('filtro-semestre'),
            initialValue: _semestreSeleccionado,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Semestre'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              ...List.generate(10, (i) => i + 1).map(
                (s) => DropdownMenuItem(value: s, child: Text('$s')),
              ),
            ],
            onChanged: (valor) =>
                setState(() => _semestreSeleccionado = valor),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _nivelSeleccionado = null;
                      _carreraSeleccionada = null;
                      _semestreSeleccionado = null;
                    });
                    _controller.aplicarFiltros();
                  },
                  child: const Text('Limpiar filtros'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _controller.aplicarFiltros(
                    nivel: _nivelSeleccionado,
                    carrera: _carreraSeleccionada,
                    semestre: _semestreSeleccionado,
                  ),
                  child: const Text('Aplicar filtros'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cuerpoLista() {
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
    if (_controller.intentos.isEmpty) {
      final hayFiltrosActivos =
          _controller.filtroNivel != null ||
          _controller.filtroCarrera != null ||
          _controller.filtroSemestre != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hayFiltrosActivos
                ? 'Ningún intento de este alumno cumple los filtros seleccionados.'
                : 'Este alumno todavía no tiene ningún intento de práctica registrado.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _controller.intentos.length + 1,
      itemBuilder: (context, index) {
        if (index == _controller.intentos.length) {
          return _piePagina();
        }
        return _FilaIntento(intento: _controller.intentos[index]);
      },
    );
  }

  Widget _piePagina() {
    if (_controller.cargandoMas) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 16);
  }
}

class _FilaIntento extends StatelessWidget {
  const _FilaIntento({required this.intento});

  final IntentoPractica intento;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(intento.palabra),
        subtitle: Text(intento.oracionAlumno),
        trailing: Text(
          formatearTiempo(Duration(seconds: intento.tiempoSegundos)),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/alumno_con_avance.dart';
import '../core/auth_controller.dart';
import '../core/carreras.dart';
import '../core/detalle_alumno_controller.dart';
import '../core/nivel.dart';
import '../core/seguimiento_alumnos_controller.dart';
import 'detalle_alumno_screen.dart';

/// RF-28, RF-30 (T-053, CU-03): panel docente de seguimiento — lista de
/// alumnos con su avance general, filtros combinables de nivel/carrera/
/// semestre, y navegación al detalle de un alumno (RF-29).
///
/// Protegido por partida doble, mismo criterio que AdminCatalogoScreen
/// (T-027): el backend ya rechaza /admin/alumnos* a quien no sea profesor
/// (RolesGuard, RNF-07); aquí además se bloquea el acceso desde la propia UI
/// si la sesión no es de profesor.
class SeguimientoAlumnosScreen extends StatefulWidget {
  const SeguimientoAlumnosScreen({
    super.key,
    required this.authController,
    this.controller,
  });

  final AuthController authController;

  /// Inyectable solo para pruebas — mismo motivo que en el resto de la app.
  final SeguimientoAlumnosController? controller;

  @override
  State<SeguimientoAlumnosScreen> createState() =>
      _SeguimientoAlumnosScreenState();
}

class _SeguimientoAlumnosScreenState extends State<SeguimientoAlumnosScreen> {
  SeguimientoAlumnosController? _controller;
  final _scrollController = ScrollController();

  // Selección PENDIENTE de los filtros — no se manda al backend hasta
  // presionar "Aplicar filtros" (RF-30): así cambiar 2 o 3 dropdowns antes
  // de buscar no dispara una llamada de red por cada toque.
  int? _nivelSeleccionado;
  String? _carreraSeleccionada;
  int? _semestreSeleccionado;

  @override
  void initState() {
    super.initState();
    final sesion = widget.authController.sesion;
    if (sesion != null && sesion.esProfesor) {
      final controller =
          widget.controller ??
          SeguimientoAlumnosController(token: sesion.token);
      _controller = controller;
      controller.cargarInicial();
      _scrollController.addListener(_alLlegarAlFinal);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _alLlegarAlFinal() {
    final controller = _controller;
    if (controller == null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      controller.cargarMas();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Seguimiento de alumnos')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta pantalla es exclusiva para profesores.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento de alumnos')),
      // _panelFiltros va DENTRO del AnimatedBuilder: su dropdown de nivel
      // depende de controller.niveles, que llega vacío en el primer build
      // (cargarInicial() todavía no resuelve) y solo se llena tras el
      // primer notifyListeners() — si el panel quedara fuera de este
      // AnimatedBuilder, el dropdown de nivel se quedaría congelado sin
      // opciones para siempre.
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          children: [
            _panelFiltros(controller),
            const Divider(height: 1),
            Expanded(child: _cuerpoLista(controller)),
          ],
        ),
      ),
    );
  }

  Widget _panelFiltros(SeguimientoAlumnosController controller) {
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
              ...controller.niveles.map(
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
                    controller.aplicarFiltros();
                  },
                  child: const Text('Limpiar filtros'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => controller.aplicarFiltros(
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

  Widget _cuerpoLista(SeguimientoAlumnosController controller) {
    if (controller.cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.cargarInicial,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (controller.alumnos.isEmpty) {
      final hayFiltrosActivos =
          controller.filtroNivel != null ||
          controller.filtroCarrera != null ||
          controller.filtroSemestre != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hayFiltrosActivos
                ? 'Ningún alumno cumple los filtros seleccionados.'
                : 'Todavía no hay alumnos registrados.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: controller.alumnos.length + 1,
      itemBuilder: (context, index) {
        if (index == controller.alumnos.length) {
          return _piePagina(controller);
        }
        final alumno = controller.alumnos[index];
        return _FilaAlumno(
          alumno: alumno,
          niveles: controller.niveles,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              // Se construye el controller aquí (en vez de dejar que
              // DetalleAlumnoScreen arme el suyo) para reutilizar el MISMO
              // AdminAlumnosService que ya tiene esta pantalla — en pruebas,
              // el mismo http.Client falso; sin esto, el detalle intentaría
              // una llamada de red real.
              builder: (_) => DetalleAlumnoScreen(
                token: controller.token,
                idAlumno: alumno.id,
                nombreAlumno: alumno.nombreCompleto,
                controller: DetalleAlumnoController(
                  token: controller.token,
                  idAlumno: alumno.id,
                  adminAlumnosService: controller.adminAlumnosService,
                  nivelesService: controller.nivelesService,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _piePagina(SeguimientoAlumnosController controller) {
    if (controller.cargandoMas) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 16);
  }
}

class _FilaAlumno extends StatelessWidget {
  const _FilaAlumno({
    required this.alumno,
    required this.niveles,
    required this.onTap,
  });

  final AlumnoConAvance alumno;
  final List<Nivel> niveles;
  final VoidCallback onTap;

  String _nombreNivel(int idNivel) {
    for (final nivel in niveles) {
      if (nivel.id == idNivel) return nivel.nombre;
    }
    return 'Nivel $idNivel';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        title: Text(alumno.nombreCompleto),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${alumno.matricula} · ${alumno.carrera} · Semestre ${alumno.semestre}',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final avance in alumno.avance)
                  Chip(
                    label: Text(
                      '${_nombreNivel(avance.idNivel)}: ${avance.palabrasPracticadas}',
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

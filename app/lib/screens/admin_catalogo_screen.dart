import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/admin_catalogo_controller.dart';
import '../core/api_exception.dart';
import '../core/auth_controller.dart';
import '../core/nivel.dart';
import '../core/palabra_admin.dart';
import '../widgets/error_backend_banner.dart';

/// RF-39 (T-027): panel de profesor para administrar el catálogo completo
/// (completas/incompletas, ocultas/visibles) — agregar, editar, subir/
/// reemplazar audio y ocultar/mostrar, todo desde esta misma pantalla
/// (diálogos, sin navegar a otras rutas).
///
/// Protegido por partida doble: el backend ya rechaza los 5 endpoints de
/// administración a quien no sea profesor (RolesGuard, RNF-07); aquí además
/// se bloquea el acceso desde la propia UI si la sesión no es de profesor,
/// para no llevar a un alumno a una pantalla que solo le daría errores 403.
class AdminCatalogoScreen extends StatefulWidget {
  const AdminCatalogoScreen({
    super.key,
    required this.authController,
    this.controller,
  });

  final AuthController authController;

  /// Inyectable solo para pruebas: sin esto, la pantalla siempre construiría
  /// su propio AdminCatalogoController con servicios por default (que a su
  /// vez usan un http.Client real) y no habría forma de darle un backend
  /// simulado en un widget test.
  final AdminCatalogoController? controller;

  @override
  State<AdminCatalogoScreen> createState() => _AdminCatalogoScreenState();
}

class _AdminCatalogoScreenState extends State<AdminCatalogoScreen> {
  AdminCatalogoController? _controller;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final sesion = widget.authController.sesion;
    if (sesion != null && sesion.esProfesor) {
      final controller =
          widget.controller ?? AdminCatalogoController(token: sesion.token);
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
      unawaited(_cargarMas(controller));
    }
  }

  // RF-38 (T-065): AdminCatalogoController.cargarMas() deliberadamente NO
  // atrapa sus propios errores (ver el comentario ahí) para que sea esta
  // pantalla quien decida cómo mostrarlos sin destruir la lista ya
  // cargada — pero antes de T-065 _alLlegarAlFinal() nunca hacía esa parte:
  // llamaba a cargarMas() sin esperarlo ni atraparlo, así que una carga
  // incremental fallida quedaba en silencio total (sin mensaje, sin forma
  // de reintentar). Separado en su propio método porque el listener del
  // ScrollController debe seguir siendo síncrono.
  Future<void> _cargarMas(AdminCatalogoController controller) async {
    try {
      await controller.cargarMas();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(
          context,
          e,
          onReintentar: () => _cargarMas(controller),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administrar catálogo')),
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
      appBar: AppBar(title: const Text('Administrar catálogo')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(context, controller),
        tooltip: 'Agregar palabra',
        child: const Icon(Icons.add),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
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
          if (controller.palabras.isEmpty) {
            return const Center(
              child: Text('Todavía no hay palabras en el catálogo.'),
            );
          }
          return ListView.builder(
            controller: _scrollController,
            itemCount: controller.palabras.length + 1,
            itemBuilder: (context, index) {
              if (index == controller.palabras.length) {
                return _piePagina(controller);
              }
              final palabra = controller.palabras[index];
              return _FilaPalabra(
                palabra: palabra,
                onEditar: () =>
                    _abrirFormulario(context, controller, existente: palabra),
                onSubirAudio: () => _subirAudio(context, controller, palabra),
                onAlternarOculta: () =>
                    _alternarOculta(context, controller, palabra),
              );
            },
          );
        },
      ),
    );
  }

  // RNF-12 sugiere explícitamente "scroll infinito con carga por lotes" — es
  // el único mecanismo de paginación (ver _alLlegarAlFinal). Deliberadamente
  // NO hay además un botón "Cargar más": combinar ambos es redundante (el
  // scroll ya dispara la carga antes de que alguien alcance a tocar un
  // botón) y en la práctica solo generaba una carrera entre los dos.
  Widget _piePagina(AdminCatalogoController controller) {
    if (controller.cargandoMas) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 16);
  }

  Future<void> _abrirFormulario(
    BuildContext context,
    AdminCatalogoController controller, {
    PalabraAdmin? existente,
  }) async {
    final resultado = await showDialog<_DatosFormulario>(
      context: context,
      builder: (_) =>
          _DialogoPalabra(niveles: controller.niveles, existente: existente),
    );
    if (resultado == null || !context.mounted) return;

    await _guardarPalabra(context, controller, resultado, existente: existente);
  }

  // RF-38 (T-065): separado de _abrirFormulario() para poder reintentar sin
  // volver a mostrar el diálogo — el diálogo YA se cerró antes de que esto
  // se llame (Navigator.pop() ocurre dentro de _DialogoPalabra al presionar
  // "Guardar", ver más abajo), así que lo único que "recuerda" lo que la
  // persona escribió es [resultado], ya capturado en memoria. Si la
  // llamada falla por backend no disponible, "Reintentar" vuelve a mandar
  // ESE MISMO [resultado] — no hace falta reabrir el diálogo ni pedirle a
  // nadie que vuelva a escribir el texto/significado/oración.
  Future<void> _guardarPalabra(
    BuildContext context,
    AdminCatalogoController controller,
    _DatosFormulario resultado, {
    PalabraAdmin? existente,
  }) async {
    try {
      if (existente == null) {
        await controller.crear(
          texto: resultado.texto,
          idNivel: resultado.idNivel,
          significadoEs: resultado.significadoEs.isEmpty
              ? null
              : resultado.significadoEs,
          oracionEjemplo: resultado.oracionEjemplo.isEmpty
              ? null
              : resultado.oracionEjemplo,
        );
      } else {
        await controller.editar(
          id: existente.id,
          texto: resultado.texto,
          idNivel: resultado.idNivel,
          significadoEs: resultado.significadoEs,
          oracionEjemplo: resultado.oracionEjemplo,
        );
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(
          context,
          e,
          onReintentar: () => _guardarPalabra(
            context,
            controller,
            resultado,
            existente: existente,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _alternarOculta(
    BuildContext context,
    AdminCatalogoController controller,
    PalabraAdmin palabra,
  ) async {
    try {
      await controller.alternarOculta(palabra);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(
          context,
          e,
          onReintentar: () => _alternarOculta(context, controller, palabra),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _subirAudio(
    BuildContext context,
    AdminCatalogoController controller,
    PalabraAdmin palabra,
  ) async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'aac', 'm4a'],
      withData: true,
    );
    if (resultado == null || resultado.files.isEmpty) return;
    final bytes = resultado.files.single.bytes;
    if (bytes == null) return;
    if (!context.mounted) return;

    await _enviarAudio(
      context,
      controller,
      palabra,
      bytes: bytes,
      nombreArchivo: resultado.files.single.name,
    );
  }

  // RF-38 (T-065): separado de _subirAudio() para poder reintentar sin
  // volver a abrir el selector de archivos — [bytes] ya está en memoria
  // (FilePicker.pickFiles(withData: true) los leyó de una vez), así que
  // "Reintentar" solo vuelve a mandar esos mismos bytes.
  Future<void> _enviarAudio(
    BuildContext context,
    AdminCatalogoController controller,
    PalabraAdmin palabra, {
    required List<int> bytes,
    required String nombreArchivo,
  }) async {
    try {
      await controller.subirAudio(
        id: palabra.id,
        bytes: bytes,
        nombreArchivo: nombreArchivo,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Audio actualizado.')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(
          context,
          e,
          onReintentar: () => _enviarAudio(
            context,
            controller,
            palabra,
            bytes: bytes,
            nombreArchivo: nombreArchivo,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _FilaPalabra extends StatelessWidget {
  const _FilaPalabra({
    required this.palabra,
    required this.onEditar,
    required this.onSubirAudio,
    required this.onAlternarOculta,
  });

  final PalabraAdmin palabra;
  final VoidCallback onEditar;
  final VoidCallback onSubirAudio;
  final VoidCallback onAlternarOculta;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onEditar,
        title: Text(palabra.texto),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(
                label: Text(palabra.completa ? 'Completa' : 'Incompleta'),
                backgroundColor: palabra.completa
                    ? Colors.green.shade100
                    : Colors.orange.shade100,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              Chip(
                label: Text(palabra.oculta ? 'Oculta' : 'Visible'),
                backgroundColor: palabra.oculta
                    ? Colors.grey.shade300
                    : Colors.blue.shade100,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.audiotrack,
                color: palabra.urlAudio != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: palabra.urlAudio == null
                  ? 'Subir audio'
                  : 'Reemplazar audio',
              onPressed: onSubirAudio,
            ),
            IconButton(
              icon: Icon(
                palabra.oculta ? Icons.visibility_off : Icons.visibility,
              ),
              tooltip: palabra.oculta ? 'Mostrar' : 'Ocultar',
              onPressed: onAlternarOculta,
            ),
          ],
        ),
      ),
    );
  }
}

class _DatosFormulario {
  const _DatosFormulario({
    required this.texto,
    required this.idNivel,
    required this.significadoEs,
    required this.oracionEjemplo,
  });

  final String texto;
  final int idNivel;
  final String significadoEs;
  final String oracionEjemplo;
}

class _DialogoPalabra extends StatefulWidget {
  const _DialogoPalabra({required this.niveles, this.existente});

  final List<Nivel> niveles;
  final PalabraAdmin? existente;

  @override
  State<_DialogoPalabra> createState() => _DialogoPalabraState();
}

class _DialogoPalabraState extends State<_DialogoPalabra> {
  final _formKey = GlobalKey<FormState>();
  late final _textoController = TextEditingController(
    text: widget.existente?.texto ?? '',
  );
  late final _significadoController = TextEditingController(
    text: widget.existente?.significadoEs ?? '',
  );
  late final _oracionController = TextEditingController(
    text: widget.existente?.oracionEjemplo ?? '',
  );
  int? _idNivel;

  @override
  void initState() {
    super.initState();
    _idNivel =
        widget.existente?.idNivel ??
        (widget.niveles.isEmpty ? null : widget.niveles.first.id);
  }

  @override
  void dispose() {
    _textoController.dispose();
    _significadoController.dispose();
    _oracionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.existente != null;
    return AlertDialog(
      title: Text(editando ? 'Editar palabra' : 'Agregar palabra'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _textoController,
                decoration: const InputDecoration(
                  labelText: 'Texto (en inglés)',
                ),
                validator: (valor) => (valor == null || valor.trim().isEmpty)
                    ? 'El texto es obligatorio.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _idNivel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nivel'),
                items: widget.niveles
                    .map(
                      (nivel) => DropdownMenuItem(
                        value: nivel.id,
                        child: Text(nivel.nombre),
                      ),
                    )
                    .toList(),
                onChanged: (valor) => setState(() => _idNivel = valor),
                validator: (valor) => valor == null ? 'Elige un nivel.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _significadoController,
                decoration: const InputDecoration(
                  labelText: 'Significado en español (opcional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _oracionController,
                decoration: const InputDecoration(
                  labelText: 'Oración de ejemplo, en inglés (opcional)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _DatosFormulario(
                texto: _textoController.text.trim(),
                idNivel: _idNivel!,
                significadoEs: _significadoController.text.trim(),
                oracionEjemplo: _oracionController.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/auth_controller.dart';
import '../core/aviso_privacidad.dart';
import '../core/carreras.dart';
import '../widgets/campo_contrasena.dart';
import '../widgets/error_backend_banner.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _matriculaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _apellidoPaternoController = TextEditingController();
  final _apellidoMaternoController = TextEditingController();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();

  String? _carrera;
  int? _semestre;
  bool _acepteAviso = false;
  bool _enviando = false;

  @override
  void dispose() {
    _matriculaController.dispose();
    _nombreController.dispose();
    _apellidoPaternoController.dispose();
    _apellidoMaternoController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    // RF-37: sin aceptar el aviso no se crea la cuenta, salga la llamada de
    // donde salga. El botón ya está deshabilitado sin la casilla, pero
    // "Reintentar" (banner de RF-38) vuelve a llamar aquí sin pasar por él:
    // con el banner todavía en pantalla se puede desmarcar la casilla.
    if (!_acepteAviso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar el aviso de privacidad.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      await widget.authController.registrar(
        matricula: _matriculaController.text.trim(),
        nombre: _nombreController.text.trim(),
        apellidoPaterno: _apellidoPaternoController.text.trim(),
        apellidoMaterno: _apellidoMaternoController.text.trim(),
        carrera: _carrera!,
        semestre: _semestre!,
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
        aceptoAvisoPrivacidad: _acepteAviso,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cuenta creada. Ya puedes iniciar sesión.'),
        ),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // RF-38 (T-065): los 8 campos siguen escritos en sus controllers pase
      // lo que pase aquí abajo — "Reintentar" solo vuelve a llamar
      // _registrar(), sin necesidad de volver a escribir nada.
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(context, e, onReintentar: _registrar);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta de alumno')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _matriculaController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Matrícula',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requerido,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nombreController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requerido,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apellidoPaternoController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Apellido paterno',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requerido,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apellidoMaternoController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Apellido materno',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requerido,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _carrera,
                      // Sin esto, "Ingeniería en Desarrollo de Software" (la
                      // opción más larga) desborda la fila del dropdown.
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Carrera',
                        border: OutlineInputBorder(),
                      ),
                      items: carreras
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (valor) => setState(() => _carrera = valor),
                      validator: (valor) =>
                          valor == null ? 'Elige tu carrera.' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _semestre,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Semestre',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(10, (i) => i + 1)
                          .map(
                            (s) =>
                                DropdownMenuItem(value: s, child: Text('$s')),
                          )
                          .toList(),
                      onChanged: (valor) => setState(() => _semestre = valor),
                      validator: (valor) =>
                          valor == null ? 'Elige tu semestre.' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _correoController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        border: OutlineInputBorder(),
                      ),
                      validator: (valor) {
                        if (valor == null || valor.trim().isEmpty) {
                          return 'Escribe tu correo.';
                        }
                        if (!valor.contains('@') || !valor.contains('.')) {
                          return 'Ese correo no parece válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CampoContrasena(
                      controller: _contrasenaController,
                      label: 'Contraseña',
                      validator: (valor) {
                        if (valor == null || valor.isEmpty) {
                          return 'Escribe una contraseña.';
                        }
                        if (valor.length < 8) {
                          return 'Debe tener al menos 8 caracteres.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _AvisoPrivacidad(
                      aceptado: _acepteAviso,
                      onChanged: (valor) {
                        setState(() => _acepteAviso = valor);
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      // El checkbox del aviso de privacidad bloquea el botón
                      // mismo (RF-37), no solo la acción tras presionarlo.
                      onPressed: (_enviando || !_acepteAviso)
                          ? null
                          : _registrar,
                      child: _enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Crear cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _requerido(String? valor) => (valor == null || valor.trim().isEmpty)
      ? 'Este campo es obligatorio.'
      : null;
}

class _AvisoPrivacidad extends StatelessWidget {
  const _AvisoPrivacidad({required this.aceptado, required this.onChanged});

  final bool aceptado;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('aviso-privacidad'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Aviso de privacidad (borrador)',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Encabezado de advertencia (T-074): EXACTO, encima del texto
              // legal y dentro de la misma tarjeta, para que no se lea el
              // aviso sin ver que es un borrador pendiente de jurídica.
              Text(
                avisoPrivacidadEncabezado,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              // Íntegro, sin maxLines ni overflow: es texto legal y tiene que
              // poder leerse completo (RF-37). Letra de cuerpo (14 sp), no la
              // pequeña (12 sp) que tenía el borrador anterior.
              Text(
                avisoPrivacidadTexto,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        CheckboxListTile(
          value: aceptado,
          onChanged: (valor) => onChanged(valor ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('Acepto el aviso de privacidad (borrador).'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/auth_controller.dart';
import '../widgets/error_backend_banner.dart';
import 'restablecer_password_screen.dart';

/// Paso 1 de RF-03: pedir el correo de restablecimiento. El backend (T-013)
/// responde el mismo mensaje genérico exista o no la cuenta — la pantalla no
/// debe insinuar lo contrario.
class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  State<RecuperarPasswordScreen> createState() =>
      _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreUsuarioController = TextEditingController();
  bool _enviando = false;
  bool _solicitudEnviada = false;

  @override
  void dispose() {
    _nombreUsuarioController.dispose();
    super.dispose();
  }

  Future<void> _solicitar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      await widget.authController.recuperarPassword(
        _nombreUsuarioController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _solicitudEnviada = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // RF-38 (T-065): "Reintentar" vuelve a llamar _solicitar(); lo escrito
      // en el campo de matrícula/usuario sigue ahí sin importar qué pase.
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(context, e, onReintentar: _solicitar);
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
      appBar: AppBar(title: const Text('Olvidé mi contraseña')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _solicitudEnviada ? _mensajeExito(context) : _formulario(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Escribe tu matrícula (alumno) o tu usuario (profesor). '
            'Si existe una cuenta, te enviaremos un correo con instrucciones.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nombreUsuarioController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _solicitar(),
            decoration: const InputDecoration(
              labelText: 'Matrícula o usuario',
              border: OutlineInputBorder(),
            ),
            validator: (valor) => (valor == null || valor.trim().isEmpty)
                ? 'Este campo es obligatorio.'
                : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _enviando ? null : _solicitar,
            child: _enviando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enviar correo de restablecimiento'),
          ),
        ],
      ),
    );
  }

  Widget _mensajeExito(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        const Text(
          'Si existe una cuenta con ese nombre de usuario, se envió un correo '
          'con instrucciones para restablecer la contraseña.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RestablecerPasswordScreen(
                authController: widget.authController,
              ),
            ),
          ),
          child: const Text('Ya tengo el código del correo'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver a iniciar sesión'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/auth_controller.dart';
import '../widgets/campo_contrasena.dart';

/// Paso 2 de RF-03: pegar el token recibido "por correo" (en dev, el log del
/// backend — no hay enlace profundo que abra la app directo en esta pantalla
/// todavía) y definir la contraseña nueva.
class RestablecerPasswordScreen extends StatefulWidget {
  const RestablecerPasswordScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  State<RestablecerPasswordScreen> createState() =>
      _RestablecerPasswordScreenState();
}

class _RestablecerPasswordScreenState extends State<RestablecerPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _contrasenaNuevaController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _contrasenaNuevaController.dispose();
    super.dispose();
  }

  Future<void> _restablecer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      await widget.authController.restablecerPassword(
        token: _tokenController.text.trim(),
        contrasenaNueva: _contrasenaNuevaController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseña restablecida. Ya puedes iniciar sesión.'),
        ),
      );
      Navigator.of(context).popUntil((ruta) => ruta.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restablecer contraseña')),
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
                    const Text(
                      'Pega el código que recibiste por correo y elige tu nueva contraseña.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _tokenController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Código de restablecimiento',
                        border: OutlineInputBorder(),
                      ),
                      validator: (valor) =>
                          (valor == null || valor.trim().isEmpty)
                          ? 'Pega el código que recibiste.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    CampoContrasena(
                      controller: _contrasenaNuevaController,
                      label: 'Contraseña nueva',
                      onFieldSubmitted: (_) => _restablecer(),
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
                    FilledButton(
                      onPressed: _enviando ? null : _restablecer,
                      child: _enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Restablecer contraseña'),
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
}

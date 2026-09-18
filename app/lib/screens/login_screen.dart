import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/auth_controller.dart';
import '../widgets/campo_contrasena.dart';
import '../widgets/error_backend_banner.dart';
import 'recuperar_password_screen.dart';
import 'registro_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreUsuarioController = TextEditingController();
  final _contrasenaController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _nombreUsuarioController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      await widget.authController.iniciarSesion(
        nombreUsuario: _nombreUsuarioController.text.trim(),
        contrasena: _contrasenaController.text,
      );
      // No hace falta navegar: AuthController notifica, y SpellingBeeApp
      // decide la pantalla siguiente (Home o cambio de contraseña forzado).
    } on ApiException catch (e) {
      if (!mounted) return;
      // RF-38 (T-065): un 5xx o una falla de red muestran el mensaje +
      // "Reintentar" (que vuelve a llamar esta misma función, con lo que ya
      // se escribió en los campos intacto — nada aquí los toca); cualquier
      // otro error (credenciales inválidas, etc.) conserva el SnackBar de
      // siempre, porque "reintentar" tal cual no serviría de nada ahí.
      if (e.esBackendNoDisponible) {
        mostrarErrorBackend(context, e, onReintentar: _iniciarSesion);
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
      appBar: AppBar(title: const Text('Iniciar sesión')),
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
                    Text(
                      'Spelling Bee',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Alumno: entra con tu matrícula. Profesor: entra con tu usuario.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _nombreUsuarioController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Matrícula o usuario',
                        border: OutlineInputBorder(),
                      ),
                      validator: (valor) =>
                          (valor == null || valor.trim().isEmpty)
                          ? 'Escribe tu matrícula o usuario.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    CampoContrasena(
                      controller: _contrasenaController,
                      label: 'Contraseña',
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _iniciarSesion(),
                      validator: (valor) => (valor == null || valor.isEmpty)
                          ? 'Escribe tu contraseña.'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _enviando
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RecuperarPasswordScreen(
                                    authController: widget.authController,
                                  ),
                                ),
                              ),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _enviando ? null : _iniciarSesion,
                      child: _enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _enviando
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RegistroScreen(
                                  authController: widget.authController,
                                ),
                              ),
                            ),
                      child: const Text('¿Eres alumno nuevo? Crea tu cuenta'),
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

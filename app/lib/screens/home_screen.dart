import 'package:flutter/material.dart';

import '../core/auth_controller.dart';
import 'admin_catalogo_screen.dart';
import 'cambiar_password_screen.dart';

/// Placeholder: el catálogo/práctica del alumno todavía no tiene pantalla
/// propia en el backlog (T-026 es solo la práctica de una palabra ya
/// elegida). Para el profesor, el botón de abajo sí es la pantalla real de
/// T-027 — es la única entrada a ella, y solo aparece con sesión de profesor.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    final sesion = authController.sesion!;
    return Scaffold(
      appBar: AppBar(title: const Text('Spelling Bee')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 56, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Sesión iniciada como ${sesion.rol}.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'El catálogo y la práctica llegan en una fase posterior del backlog.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (sesion.esProfesor) ...[
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminCatalogoScreen(authController: authController),
                    ),
                  ),
                  child: const Text('Administrar catálogo'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CambiarPasswordScreen(authController: authController),
                  ),
                ),
                child: const Text('Cambiar mi contraseña'),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => authController.cerrarSesion(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

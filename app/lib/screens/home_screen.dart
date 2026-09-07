import 'package:flutter/material.dart';

import '../core/auth_controller.dart';
import 'cambiar_password_screen.dart';

/// Placeholder: el catálogo/práctica real es de la Fase 2 (T-020 en
/// adelante), todavía sin backend que consumir. Esta pantalla solo prueba que
/// login/logout/cambio voluntario de contraseña (T-011, T-012, T-014) ya
/// funcionan de punta a punta desde la app.
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/auth_controller.dart';
import '../core/cola_practica_archivo.dart';
import '../core/sincronizador_practica.dart';
import 'admin_catalogo_screen.dart';
import 'cambiar_password_screen.dart';
import 'niveles_screen.dart';
import 'perfil_progreso_screen.dart';
import 'seguimiento_alumnos_screen.dart';

/// Placeholder: el catálogo/práctica del alumno todavía no tiene pantalla
/// propia en el backlog (T-026 es solo la práctica de una palabra ya
/// elegida). Para el profesor, el botón de abajo sí es la pantalla real de
/// T-027 — es la única entrada a ella, y solo aparece con sesión de profesor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.authController, this.sincronizador});

  final AuthController authController;

  /// Inyectable solo para pruebas — mismo motivo que en el resto de la app.
  /// En producción, HomeScreen es el ÚNICO lugar que crea este objeto (RF-33,
  /// T-062): vive mientras dure la sesión del alumno, no una pantalla —
  /// arranca aquí en initState() y se cierra aquí en dispose(), para que el
  /// temporizador de reintento cada 5 minutos siga corriendo aunque el
  /// alumno navegue entre NivelesScreen/PracticaPalabraScreen (ver el
  /// comentario de SincronizadorPractica).
  final SincronizadorPractica? sincronizador;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SincronizadorPractica? _sincronizador;

  @override
  void initState() {
    super.initState();
    final sesion = widget.authController.sesion!;
    // Un profesor nunca practica (RF-33 es sobre registros de práctica del
    // alumno) — no tiene sentido arrancar la cola/temporizador para él.
    if (!sesion.esProfesor) {
      _sincronizador =
          widget.sincronizador ??
          SincronizadorPractica(
            cola: ColaPracticaArchivo(),
            token: sesion.token,
          );
      unawaited(_sincronizador!.iniciar());
    }
  }

  @override
  void dispose() {
    _sincronizador?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sesion = widget.authController.sesion!;
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
                          AdminCatalogoScreen(authController: widget.authController),
                    ),
                  ),
                  child: const Text('Administrar catálogo'),
                ),
                const SizedBox(height: 12),
                // RF-28 a RF-30 (T-053, CU-03): panel docente de seguimiento
                // — solo tiene sentido para el profesor, un alumno no
                // consulta el progreso de otros.
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SeguimientoAlumnosScreen(
                        authController: widget.authController,
                      ),
                    ),
                  ),
                  child: const Text('Seguimiento de alumnos'),
                ),
                const SizedBox(height: 12),
              ] else ...[
                // RF-31/RF-32 (T-061): descargar niveles y practicar, con o
                // sin conexión — único punto de entrada, igual que
                // "Administrar catálogo" lo es para el profesor.
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NivelesScreen(
                        token: sesion.token,
                        sincronizador: _sincronizador,
                      ),
                    ),
                  ),
                  child: const Text('Practicar'),
                ),
                const SizedBox(height: 12),
                // RF-24 (T-047): insignias por nivel completado — solo tiene
                // sentido para el alumno, un profesor no practica palabras.
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PerfilProgresoScreen(token: sesion.token),
                    ),
                  ),
                  child: const Text('Mi progreso'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CambiarPasswordScreen(authController: widget.authController),
                  ),
                ),
                child: const Text('Cambiar mi contraseña'),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => widget.authController.cerrarSesion(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

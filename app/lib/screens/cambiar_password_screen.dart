import 'package:flutter/material.dart';

import '../core/api_exception.dart';
import '../core/auth_controller.dart';
import '../widgets/campo_contrasena.dart';

/// RF-35 (cambio voluntario) y RF-36 (cambio forzado en el primer login).
///
/// [obligatorio] controla las dos diferencias entre ambos casos: sin barra de
/// "atrás" y sin poder cancelar con el botón/gesto de atrás del sistema. La
/// llamada al backend y el formulario son exactamente los mismos.
class CambiarPasswordScreen extends StatefulWidget {
  const CambiarPasswordScreen({
    super.key,
    required this.authController,
    this.obligatorio = false,
  });

  final AuthController authController;
  final bool obligatorio;

  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      await widget.authController.cambiarPassword(
        contrasenaActual: _actualController.text,
        contrasenaNueva: _nuevaController.text,
      );
      if (!mounted) return;
      if (widget.obligatorio) {
        // No hay que navegar: AuthController ya notificó que
        // debeCambiarContrasena pasó a false, y SpellingBeeApp cambia de
        // pantalla sola (ver main.dart) — no queda nada más que hacer aquí.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada.')),
        );
        Navigator.of(context).pop();
      }
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
    return PopScope(
      // RF-36: en el cambio obligatorio no hay forma de salir de esta
      // pantalla sin completar el cambio — ni con el botón, ni con el gesto
      // de atrás del sistema.
      canPop: !widget.obligatorio,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cambiar contraseña'),
          automaticallyImplyLeading: !widget.obligatorio,
        ),
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
                      if (widget.obligatorio) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Tu contraseña es temporal. Debes definir una nueva '
                            'antes de continuar.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      CampoContrasena(
                        controller: _actualController,
                        label: 'Contraseña actual',
                        textInputAction: TextInputAction.next,
                        validator: (valor) => (valor == null || valor.isEmpty)
                            ? 'Escribe tu contraseña actual.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      CampoContrasena(
                        controller: _nuevaController,
                        label: 'Contraseña nueva',
                        textInputAction: TextInputAction.next,
                        validator: (valor) {
                          if (valor == null || valor.isEmpty) {
                            return 'Escribe una contraseña nueva.';
                          }
                          if (valor.length < 8) {
                            return 'Debe tener al menos 8 caracteres.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      CampoContrasena(
                        controller: _confirmarController,
                        label: 'Confirmar contraseña nueva',
                        onFieldSubmitted: (_) => _cambiar(),
                        validator: (valor) => (valor != _nuevaController.text)
                            ? 'No coincide con la contraseña nueva.'
                            : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _enviando ? null : _cambiar,
                        child: _enviando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Guardar contraseña nueva'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

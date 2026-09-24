import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spelling_bee/core/auth_controller.dart';
import 'package:spelling_bee/main.dart';
import 'package:spelling_bee/screens/registro_screen.dart';

void main() {
  testWidgets('sin sesión guardada, la app abre en la pantalla de login', (
    WidgetTester tester,
  ) async {
    // No se llama cargarSesionGuardada(): no hay sesión que cargar, así que
    // el AuthController se queda tal como arranca (sin sesión), sin tocar
    // flutter_secure_storage (no disponible en el entorno de test).
    final authController = AuthController();

    await tester.pumpWidget(SpellingBeeApp(authController: authController));

    expect(find.text('Iniciar sesión'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });

  testWidgets(
    'el formulario de login rechaza campos vacíos sin llamar a la red',
    (WidgetTester tester) async {
      final authController = AuthController();
      await tester.pumpWidget(SpellingBeeApp(authController: authController));

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();

      expect(find.text('Escribe tu matrícula o usuario.'), findsOneWidget);
      expect(find.text('Escribe tu contraseña.'), findsOneWidget);
    },
  );

  testWidgets('desde login se puede navegar a la pantalla de registro', (
    WidgetTester tester,
  ) async {
    final authController = AuthController();
    await tester.pumpWidget(SpellingBeeApp(authController: authController));

    await tester.tap(find.text('¿Eres alumno nuevo? Crea tu cuenta'));
    await tester.pumpAndSettle();

    expect(find.byType(RegistroScreen), findsOneWidget);
    // RF-37 / T-074: el aviso de privacidad debe verse en el registro, y
    // marcado con claridad como borrador (el encabezado y la advertencia que
    // trae el propio texto). El texto exacto y su legibilidad se prueban a
    // fondo en registro_screen_test.dart.
    expect(find.text('Aviso de privacidad (borrador)'), findsOneWidget);
    expect(
      find.text('BORRADOR — PENDIENTE DE VALIDACIÓN JURÍDICA'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Este texto es un borrador temporal de trabajo.'),
      findsOneWidget,
    );
  });
}

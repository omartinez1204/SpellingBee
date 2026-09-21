import 'package:flutter/material.dart';

import 'core/auth_controller.dart';
import 'core/localizacion.dart';
import 'screens/cambiar_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authController = AuthController();
  await authController.cargarSesionGuardada();
  runApp(SpellingBeeApp(authController: authController));
}

class SpellingBeeApp extends StatelessWidget {
  const SpellingBeeApp({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spelling Bee',
      debugShowCheckedModeBanner: false,
      // RNF-01 (T-071): idioma fijo en español, también para los textos que
      // pone el propio Flutter (ver core/localizacion.dart).
      locale: localeDeLaInterfaz,
      supportedLocales: localesSoportados,
      localizationsDelegates: delegadosDeLocalizacion,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // ListenableBuilder decide la pantalla raíz según el estado de sesión.
      // RF-36 queda garantizado a este nivel: mientras debeCambiarContrasena
      // sea true, no hay ruta ni gesto que lleve a HomeScreen, porque
      // HomeScreen ni siquiera se construye.
      home: ListenableBuilder(
        listenable: authController,
        builder: (context, _) {
          final sesion = authController.sesion;
          if (sesion == null) {
            return LoginScreen(authController: authController);
          }
          if (sesion.debeCambiarContrasena) {
            return CambiarPasswordScreen(
              authController: authController,
              obligatorio: true,
            );
          }
          return HomeScreen(authController: authController);
        },
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spelling_bee/core/api_client.dart';
import 'package:spelling_bee/core/auth_controller.dart';
import 'package:spelling_bee/core/localizacion.dart';
import 'package:spelling_bee/screens/registro_screen.dart';

import 'helpers/textos_espanol.dart';

/// RF-38 (T-065): representa el patrón aplicado por igual a los 5
/// formularios de autenticación (login, registro, cambiar/recuperar/
/// restablecer contraseña) — se prueba a fondo aquí, con el formulario de
/// MÁS campos de toda la app, porque es donde "no perder lo ya capturado"
/// importa más; el resto comparte el mismo mecanismo (ApiException.
/// esBackendNoDisponible + mostrarErrorBackend), ya cubierto por
/// error_backend_banner_test.dart y api_client_test.dart.
class _ClienteQueFallaLuegoOk extends http.BaseClient {
  final List<http.Request> peticiones = [];
  var _yaFallo = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) peticiones.add(request);
    if (!_yaFallo) {
      _yaFallo = true;
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      201,
      headers: {'content-type': 'application/json'},
    );
  }
}

// T-071: misma localización que la app real (core/localizacion.dart), para que
// los textos que pone el propio Flutter también salgan en español aquí.
Widget _envolver(Widget child) => MaterialApp(
  locale: localeDeLaInterfaz,
  supportedLocales: localesSoportados,
  localizationsDelegates: delegadosDeLocalizacion,
  home: child,
  debugShowCheckedModeBanner: false,
);

Future<void> _llenarFormulario(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Matrícula'),
    '2024001',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Nombre'),
    'Ada',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Apellido paterno'),
    'Lovelace',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Apellido materno'),
    'Byron',
  );
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Carrera'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ingeniería en Desarrollo de Software').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Semestre'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('3').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Correo electrónico'),
    'ada@example.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Contraseña'),
    'ClaveSegura123',
  );
  final checkbox = find.widgetWithText(
    CheckboxListTile,
    'Acepto el aviso de privacidad (borrador).',
  );
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pump();
}

void main() {
  testWidgets(
    'RF-38 (T-065): si el registro falla por un 5xx, muestra el banner de reintentar sin perder ningún campo, y Reintentar sí crea la cuenta',
    (tester) async {
      // Viewport de prueba por default (800x600) es demasiado angosto/bajo
      // para este formulario de 8 campos + el menú desplegable de 10
      // semestres totalmente abierto: sin esto, algunos elementos quedan
      // fuera del área "visible" para el hit-test de tap(), o el menú del
      // dropdown se queda abierto (su barrera modal, no un problema real de
      // la pantalla) y bloquea toques posteriores.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cliente = _ClienteQueFallaLuegoOk();
      final auth = AuthController(apiClient: ApiClient(httpClient: cliente));

      await tester.pumpWidget(_envolver(RegistroScreen(authController: auth)));
      await tester.pumpAndSettle();

      await _llenarFormulario(tester);

      final botonCrear = find.widgetWithText(FilledButton, 'Crear cuenta');
      await tester.ensureVisible(botonCrear);
      await tester.tap(botonCrear);
      await tester.pumpAndSettle();

      expect(
        cliente.peticiones,
        hasLength(1),
        reason: 'el primer intento falló con 500',
      );
      expect(find.byType(MaterialBanner), findsOneWidget);
      // RF-38: los 8 campos siguen ahí, ninguno se limpió por el error.
      expect(find.text('2024001'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Lovelace'), findsOneWidget);
      expect(find.text('Byron'), findsOneWidget);
      expect(find.text('Ingeniería en Desarrollo de Software'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      final campoContrasena = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).last,
          matching: find.byType(TextField),
        ),
      );
      expect(campoContrasena.controller!.text, 'ClaveSegura123');
      // T-071 (RNF-01): el formulario lleno y el banner de error, en español.
      await expectSoloEspanol(
        tester,
        pantalla: 'registro con el servidor caído (banner de reintentar)',
      );

      final botonReintentar = find.widgetWithText(TextButton, 'Reintentar');
      await tester.ensureVisible(botonReintentar);
      await tester.tap(botonReintentar);
      // Ni un solo pump() (el MaterialBanner tarda su propia animación en
      // salir) ni pumpAndSettle() (el SnackBar de éxito se cierra solo
      // pasado su duration de ~4s, y pumpAndSettle() avanzaría el reloj
      // falso a través de todo su ciclo antes de que el expect() de abajo
      // alcance a verlo): un pump() sin duración deja resolver la petición
      // de red (async, sin retraso real) y uno con duración acotada deja
      // completar las animaciones de salida/entrada sin llegar a los ~4s.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        cliente.peticiones,
        hasLength(2),
        reason: 'Reintentar debió mandar OTRA petición con los mismos datos',
      );
      final segundoIntento =
          jsonDecode(cliente.peticiones.last.body) as Map<String, dynamic>;
      expect(segundoIntento['matricula'], '2024001');
      expect(segundoIntento['correo'], 'ada@example.com');
      // Prueba indirecta pero suficiente de que el reintento tuvo ÉXITO
      // (y no solo que se mandó): si hubiera fallado de nuevo, el banner de
      // error volvería a aparecer. No se verifica el SnackBar de éxito en
      // sí (su ciclo de mostrar/cerrarse solo es más frágil de cronometrar
      // en la prueba) — no es lo que RF-38/T-065 necesita demostrar aquí.
      expect(find.byType(MaterialBanner), findsNothing);
    },
  );
}

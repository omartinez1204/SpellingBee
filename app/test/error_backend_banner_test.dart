import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/api_exception.dart';
import 'package:spelling_bee/widgets/error_backend_banner.dart';

void main() {
  Widget envolver(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'RF-38: muestra el mensaje del error y un botón Reintentar, sin desmontar el contenido debajo',
    (tester) async {
      late BuildContext contextoCapturado;
      await tester.pumpWidget(
        envolver(
          Builder(
            builder: (context) {
              contextoCapturado = context;
              return const Text('formulario en curso: "mi oración"');
            },
          ),
        ),
      );

      mostrarErrorBackend(
        contextoCapturado,
        const ApiException(
          'SIN_CONEXION',
          'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
        ),
        onReintentar: () {},
      );
      await tester.pump();

      expect(
        find.text(
          'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
      expect(
        find.text('formulario en curso: "mi oración"'),
        findsOneWidget,
        reason: 'RF-38: el contenido de abajo debe seguir presente, no ser reemplazado por el banner',
      );
    },
  );

  testWidgets(
    'RF-38: tocar Reintentar llama a onReintentar y cierra el banner',
    (tester) async {
      late BuildContext contextoCapturado;
      var vecesReintentado = 0;
      await tester.pumpWidget(
        envolver(
          Builder(
            builder: (context) {
              contextoCapturado = context;
              return const SizedBox();
            },
          ),
        ),
      );

      mostrarErrorBackend(
        contextoCapturado,
        const ApiException('ERROR_INTERNO', 'Ocurrió un error inesperado.'),
        onReintentar: () => vecesReintentado++,
      );
      // pumpAndSettle(), no un solo pump(): el MaterialBanner entra con una
      // animación — un solo frame puede dejar el botón todavía fuera del
      // área visible (a medio deslizar), y tap() fallaría el hit-test.
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(vecesReintentado, 1);
      expect(find.byType(MaterialBanner), findsNothing);
    },
  );

  testWidgets(
    'RF-38: tocar Cerrar descarta el banner sin llamar a onReintentar',
    (tester) async {
      late BuildContext contextoCapturado;
      var vecesReintentado = 0;
      await tester.pumpWidget(
        envolver(
          Builder(
            builder: (context) {
              contextoCapturado = context;
              return const SizedBox();
            },
          ),
        ),
      );

      mostrarErrorBackend(
        contextoCapturado,
        const ApiException('ERROR_INTERNO', 'Ocurrió un error inesperado.'),
        onReintentar: () => vecesReintentado++,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cerrar'));
      await tester.pumpAndSettle();

      expect(vecesReintentado, 0);
      expect(find.byType(MaterialBanner), findsNothing);
    },
  );

  testWidgets(
    'RF-38: si la pantalla que lanzó la operación ya se desmontó, Reintentar NO ejecuta su callback (solo descarta el banner)',
    (tester) async {
      late BuildContext contextoDeLaPantalla;
      var vecesReintentado = 0;
      final pantallaVisible = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        envolver(
          ValueListenableBuilder<bool>(
            valueListenable: pantallaVisible,
            builder: (context, visible, _) => visible
                ? Builder(
                    builder: (context) {
                      contextoDeLaPantalla = context;
                      return const Text('pantalla que lanzó la operación');
                    },
                  )
                : const Text('otra pantalla'),
          ),
        ),
      );

      mostrarErrorBackend(
        contextoDeLaPantalla,
        const ApiException('ERROR_INTERNO', 'Ocurrió un error inesperado.'),
        onReintentar: () => vecesReintentado++,
      );
      await tester.pumpAndSettle();

      // La pantalla desaparece, pero el banner (que vive en el
      // ScaffoldMessenger, por encima) sigue visible.
      pantallaVisible.value = false;
      await tester.pump();
      expect(find.text('pantalla que lanzó la operación'), findsNothing);
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(
        vecesReintentado,
        0,
        reason: 'el callback pertenece a una pantalla ya destruida — ejecutarlo podría mandar datos vacíos o tronar',
      );
      expect(find.byType(MaterialBanner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RF-38: el banner se cierra solo cuando la ruta que lo mostró sale de la pila (no queda huérfano en la pantalla de atrás)',
    (tester) async {
      await tester.pumpWidget(
        envolver(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (contextoDePantallaNueva) => TextButton(
                        onPressed: () => mostrarErrorBackend(
                          contextoDePantallaNueva,
                          const ApiException(
                            'ERROR_INTERNO',
                            'Ocurrió un error inesperado.',
                          ),
                          onReintentar: () {},
                        ),
                        child: const Text('provocar error'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('abrir pantalla'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir pantalla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('provocar error'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsOneWidget);

      // Salir de la pantalla nueva (equivale a tocar "atrás").
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('abrir pantalla'), findsOneWidget);
      expect(
        find.byType(MaterialBanner),
        findsNothing,
        reason: 'el banner pertenecía a la pantalla que ya salió — no debe quedarse flotando en la de atrás',
      );
    },
  );

  testWidgets(
    'una llamada nueva reemplaza el banner anterior en vez de apilarlos',
    (tester) async {
      late BuildContext contextoCapturado;
      await tester.pumpWidget(
        envolver(
          Builder(
            builder: (context) {
              contextoCapturado = context;
              return const SizedBox();
            },
          ),
        ),
      );

      mostrarErrorBackend(
        contextoCapturado,
        const ApiException('SIN_CONEXION', 'Primer error.'),
        onReintentar: () {},
      );
      await tester.pump();
      mostrarErrorBackend(
        contextoCapturado,
        const ApiException('SIN_CONEXION', 'Segundo error.'),
        onReintentar: () {},
      );
      await tester.pump();

      expect(find.text('Primer error.'), findsNothing);
      expect(find.text('Segundo error.'), findsOneWidget);
    },
  );
}

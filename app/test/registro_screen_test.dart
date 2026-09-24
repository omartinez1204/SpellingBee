import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// T-074 (RF-37): responde 201 a todo; guarda las peticiones para poder mirar
/// qué se mandó (y, sobre todo, qué NO se mandó).
class _ClienteQueSiempreOk extends http.BaseClient {
  final List<http.Request> peticiones = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) peticiones.add(request);
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

/// Igual que [_envolver], con la letra del sistema ampliada [escala] veces
/// (Ajustes > Accesibilidad > Tamaño de fuente en el teléfono).
Widget _envolverConEscala(Widget child, double escala) => MaterialApp(
  locale: localeDeLaInterfaz,
  supportedLocales: localesSoportados,
  localizationsDelegates: delegadosDeLocalizacion,
  builder: (context, hijo) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
    child: hijo!,
  ),
  home: child,
  debugShowCheckedModeBanner: false,
);

// T-074 (RF-37): texto EXACTO del aviso de privacidad, tal como lo entregó el
// equipo de desarrollo (borrador provisional). Es una copia INDEPENDIENTE de
// la constante de lib/core/aviso_privacidad.dart a propósito: si alguien
// "corrige" el texto legal en el código, esta prueba falla — el contenido
// definitivo lo redacta y valida el área jurídica (RNF-11), no el desarrollo.
// Cuando llegue el definitivo se cambia en los dos lugares, a la vez.
const _avisoEsperado =
    'La Universidad NovaUniversitas, es responsable del tratamiento de tus datos personales conforme a esta app. '
    'Los datos que recabamos en tu registro (nombre, matrícula, carrera, semestre y demás campos solicitados) se usan únicamente para identificarte, darte seguimiento a tu progreso de práctica de inglés dentro de esta plataforma, y para que tus profesores puedan revisar tu avance. '
    'No compartimos tus datos con terceros ajenos a NovaUniversitas. '
    'Puedes ejercer tus derechos de acceso, rectificación, cancelación u oposición (derechos ARCO) escribiendo a noreply@novauniversitas.edu.mx.\n\n'
    'Este texto es un borrador temporal de trabajo. '
    'El contenido definitivo será redactado y validado por el área jurídica de NovaUniversitas antes del lanzamiento a producción de la aplicación móvil.  '
    'Atentamente: Equipo de desarrollo de la universidad';

// T-074 (RF-37): encabezado de advertencia que va ENCIMA del texto legal, tal
// como se indicó en la revisión de T-074. No es parte del texto legal (ese es
// _avisoEsperado, que no se toca): es la marca de borrador, y se quita cuando
// llegue el aviso definitivo de jurídica. Copia independiente de la constante
// de lib/core/aviso_privacidad.dart, por el mismo motivo.
const _encabezadoEsperado = 'BORRADOR — PENDIENTE DE VALIDACIÓN JURÍDICA';

const _etiquetaCasilla = 'Acepto el aviso de privacidad (borrador).';

Future<void> _llenarFormulario(
  WidgetTester tester, {
  bool aceptarAviso = true,
}) async {
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
  if (!aceptarAviso) return;
  final checkbox = find.widgetWithText(CheckboxListTile, _etiquetaCasilla);
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

  // T-074 (RF-37): "El registro de un alumno no puede completarse sin marcar
  // la casilla de aceptación del aviso de privacidad; el texto completo del
  // aviso es accesible desde la pantalla de registro." Aquí, además, el texto
  // va íntegro EN la pantalla (no detrás de un enlace) y ANTES de la casilla.
  group('RF-37 (T-074): aviso de privacidad en el registro', () {
    // Teléfono de 360 dp de ancho (el caso apretado); alto de sobra para que
    // todo el formulario quepa sin desplazarse.
    Future<void> abrirEnTelefono(
      WidgetTester tester, {
      double escala = 1.0,
    }) async {
      tester.view.physicalSize = const Size(360, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _envolverConEscala(RegistroScreen(authController: AuthController()), escala),
      );
      await tester.pumpAndSettle();
    }

    void vistaAnchaYAlta(WidgetTester tester) {
      // Mismo motivo que en la prueba de RF-38: el formulario de 8 campos y los
      // menús desplegables no caben en el viewport por defecto (800x600).
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'muestra el texto EXACTO entregado, íntegro y sin tocar nada: ni enlaces ni pasos previos',
      (tester) async {
        await abrirEnTelefono(tester);

        final texto = find.text(_avisoEsperado);
        expect(texto, findsOneWidget);
        final widgetTexto = tester.widget<Text>(texto);
        expect(widgetTexto.maxLines, isNull, reason: 'sin límite de líneas');
        expect(widgetTexto.overflow, isNull, reason: 'sin elipsis ni recorte');
        expect(
          tester.renderObject<RenderParagraph>(texto).didExceedMaxLines,
          isFalse,
        );

        // Marcado como borrador: el título de la tarjeta (con su ícono de
        // advertencia) y el encabezado de advertencia, EXACTO, dentro de la
        // tarjeta y ENCIMA del texto legal.
        final tarjeta = find.byKey(const Key('aviso-privacidad'));
        expect(tarjeta, findsOneWidget);
        expect(
          find.descendant(
            of: tarjeta,
            matching: find.text('Aviso de privacidad (borrador)'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tarjeta, matching: find.byIcon(Icons.warning_amber)),
          findsOneWidget,
        );
        final encabezado = find.descendant(
          of: tarjeta,
          matching: find.text(_encabezadoEsperado),
        );
        expect(encabezado, findsOneWidget);
        expect(
          tester.getBottomLeft(encabezado).dy,
          lessThanOrEqualTo(tester.getTopLeft(texto).dy),
          reason: 'el encabezado de advertencia va antes del texto legal',
        );

        // "Accesible" también para un lector de pantalla (TalkBack): ambos
        // textos, exactos, están en el árbol de semántica.
        final anunciados = await textosDePantalla(tester);
        expect(anunciados, containsAll([_encabezadoEsperado, _avisoEsperado]));

        // No está detrás de un enlace ni de un botón: dentro de la tarjeta solo
        // hay ícono y texto — nada que tocar para poder leerlo.
        expect(
          find.descendant(
            of: tarjeta,
            matching: find.byWidgetPredicate(
              (w) => w is ButtonStyleButton || w is InkResponse || w is GestureDetector,
            ),
          ),
          findsNothing,
        );

        // T-071 (RNF-01): el texto legal tampoco mete inglés en la interfaz.
        await expectSoloEspanol(tester, pantalla: 'registro con el aviso de privacidad');
      },
    );

    testWidgets(
      'es legible: letra de cuerpo (14 sp o más) y sigue íntegro con la letra del sistema al 150 % y al 200 %',
      (tester) async {
        final alturas = <double>[];
        for (final escala in [1.0, 1.5, 2.0]) {
          await abrirEnTelefono(tester, escala: escala);

          final texto = find.text(_avisoEsperado);
          expect(texto, findsOneWidget, reason: 'escala $escala');
          final parrafo = tester.renderObject<RenderParagraph>(texto);
          expect(parrafo.didExceedMaxLines, isFalse, reason: 'escala $escala');
          expect(
            parrafo.text.style!.fontSize!,
            greaterThanOrEqualTo(14),
            reason: 'tamaño de letra del aviso (sp), escala $escala',
          );
          expect(tester.takeException(), isNull, reason: 'sin desbordes a escala $escala');
          alturas.add(parrafo.size.height);

          // El encabezado de advertencia también se lee completo y sin recorte.
          final encabezado = find.text(_encabezadoEsperado);
          expect(encabezado, findsOneWidget, reason: 'encabezado, escala $escala');
          final parrafoEncabezado = tester.renderObject<RenderParagraph>(encabezado);
          expect(parrafoEncabezado.didExceedMaxLines, isFalse, reason: 'encabezado, escala $escala');
          expect(
            parrafoEncabezado.text.style!.fontSize!,
            greaterThanOrEqualTo(14),
            reason: 'tamaño de letra del encabezado (sp), escala $escala',
          );
        }
        // Comprobación de que la escala SÍ se aplicó (si no, las tres corridas
        // medirían lo mismo y la prueba no probaría nada).
        expect(alturas[1], greaterThan(alturas[0]));
        expect(alturas[2], greaterThan(alturas[1]));
      },
    );

    testWidgets(
      'el texto va ANTES de la casilla: está en pantalla desde el primer fotograma y termina por encima de ella',
      (tester) async {
        tester.view.physicalSize = const Size(360, 3200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // UN solo pump, sin ninguna interacción: el aviso ya está ahí.
        await tester.pumpWidget(
          _envolver(RegistroScreen(authController: AuthController())),
        );
        expect(find.text(_avisoEsperado), findsOneWidget);
        await tester.pumpAndSettle();

        final casilla = find.widgetWithText(CheckboxListTile, _etiquetaCasilla);
        expect(casilla, findsOneWidget);
        expect(tester.widget<CheckboxListTile>(casilla).value, isFalse, reason: 'arranca sin marcar');
        expect(
          tester.getBottomLeft(find.text(_avisoEsperado)).dy,
          lessThanOrEqualTo(tester.getTopLeft(casilla).dy),
          reason: 'el texto debe terminar antes de que empiece la casilla',
        );
      },
    );

    testWidgets(
      'la casilla nunca se puede marcar sin el aviso a la vista: encabezado y texto completos están presentes al abrir, con la casilla marcada, con el banner de error y con la casilla desmarcada',
      (tester) async {
        vistaAnchaYAlta(tester);
        final cliente = _ClienteQueFallaLuegoOk();
        final auth = AuthController(apiClient: ApiClient(httpClient: cliente));
        await tester.pumpWidget(_envolver(RegistroScreen(authController: auth)));
        await tester.pumpAndSettle();

        final casilla = find.widgetWithText(CheckboxListTile, _etiquetaCasilla);
        void avisoCompletoALaVista(String momento) {
          expect(find.text(_encabezadoEsperado), findsOneWidget, reason: momento);
          expect(find.text(_avisoEsperado), findsOneWidget, reason: momento);
          expect(casilla, findsOneWidget, reason: momento);
          // Y el aviso termina ANTES de que empiece la casilla.
          expect(
            tester.getBottomLeft(find.text(_avisoEsperado)).dy,
            lessThanOrEqualTo(tester.getTopLeft(casilla).dy),
            reason: momento,
          );
        }

        avisoCompletoALaVista('al abrir');

        await _llenarFormulario(tester); // deja la casilla marcada
        expect(tester.widget<CheckboxListTile>(casilla).value, isTrue);
        avisoCompletoALaVista('con la casilla marcada');

        final botonCrear = find.widgetWithText(FilledButton, 'Crear cuenta');
        await tester.ensureVisible(botonCrear);
        await tester.tap(botonCrear);
        await tester.pumpAndSettle();
        expect(find.byType(MaterialBanner), findsOneWidget);
        avisoCompletoALaVista('con el banner de error');

        await tester.ensureVisible(casilla);
        await tester.tap(casilla);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(casilla).value, isFalse);
        avisoCompletoALaVista('con la casilla desmarcada');
      },
    );

    testWidgets(
      'la casilla es obligatoria: sin marcarla el botón está deshabilitado y no sale ninguna petición; marcada, se manda acepto_aviso_privacidad: true',
      (tester) async {
        vistaAnchaYAlta(tester);
        final cliente = _ClienteQueSiempreOk();
        final auth = AuthController(apiClient: ApiClient(httpClient: cliente));
        await tester.pumpWidget(_envolver(RegistroScreen(authController: auth)));
        await tester.pumpAndSettle();

        await _llenarFormulario(tester, aceptarAviso: false);

        final boton = find.widgetWithText(FilledButton, 'Crear cuenta');
        await tester.ensureVisible(boton);
        expect(tester.widget<FilledButton>(boton).onPressed, isNull);
        await tester.tap(boton, warnIfMissed: false);
        await tester.pump();
        expect(cliente.peticiones, isEmpty, reason: 'sin aceptar el aviso no se manda nada');

        final casilla = find.widgetWithText(CheckboxListTile, _etiquetaCasilla);
        await tester.ensureVisible(casilla);
        await tester.tap(casilla);
        await tester.pump();
        expect(tester.widget<FilledButton>(boton).onPressed, isNotNull);

        // Desmarcarla de nuevo vuelve a bloquear el botón.
        await tester.tap(casilla);
        await tester.pump();
        expect(tester.widget<FilledButton>(boton).onPressed, isNull);

        await tester.tap(casilla);
        await tester.pump();
        await tester.tap(boton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(cliente.peticiones, hasLength(1));
        final cuerpo = jsonDecode(cliente.peticiones.single.body) as Map<String, dynamic>;
        expect(cuerpo['acepto_aviso_privacidad'], isTrue);
      },
    );

    testWidgets(
      'no se salta la casilla con "Reintentar": tras un 5xx, desmarcarla y reintentar NO crea la cuenta y avisa; al volver a marcarla, sí',
      (tester) async {
        vistaAnchaYAlta(tester);
        final cliente = _ClienteQueFallaLuegoOk();
        final auth = AuthController(apiClient: ApiClient(httpClient: cliente));
        await tester.pumpWidget(_envolver(RegistroScreen(authController: auth)));
        await tester.pumpAndSettle();

        await _llenarFormulario(tester);
        final botonCrear = find.widgetWithText(FilledButton, 'Crear cuenta');
        await tester.ensureVisible(botonCrear);
        await tester.tap(botonCrear);
        await tester.pumpAndSettle();
        expect(cliente.peticiones, hasLength(1), reason: 'el primer intento falló con 500');
        expect(find.byType(MaterialBanner), findsOneWidget);

        // La persona cambia de opinión con el banner todavía en pantalla.
        final casilla = find.widgetWithText(CheckboxListTile, _etiquetaCasilla);
        await tester.ensureVisible(casilla);
        await tester.tap(casilla);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(casilla).value, isFalse);

        final reintentar = find.widgetWithText(TextButton, 'Reintentar');
        await tester.ensureVisible(reintentar);
        await tester.tap(reintentar);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          cliente.peticiones,
          hasLength(1),
          reason: 'sin la casilla marcada no puede salir ninguna petición nueva',
        );
        expect(find.text('Debes aceptar el aviso de privacidad.'), findsOneWidget);

        // Vuelve a aceptar y crea la cuenta: ahora sí sale, y con true.
        await tester.ensureVisible(casilla);
        await tester.tap(casilla);
        await tester.pump();
        await tester.ensureVisible(botonCrear);
        await tester.tap(botonCrear);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(cliente.peticiones, hasLength(2));
        final cuerpo = jsonDecode(cliente.peticiones.last.body) as Map<String, dynamic>;
        expect(cuerpo['acepto_aviso_privacidad'], isTrue);
      },
    );
  });
}

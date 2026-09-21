import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/auth_controller.dart';
import 'package:spelling_bee/core/localizacion.dart';
import 'package:spelling_bee/main.dart';
import 'package:spelling_bee/screens/cambiar_password_screen.dart';
import 'package:spelling_bee/screens/restablecer_password_screen.dart';

import 'helpers/textos_espanol.dart';

// T-071 (RNF-01): "Toda la interfaz (menús, botones, mensajes) debe estar en
// español; únicamente el contenido léxico a practicar (la palabra y su oración
// de ejemplo) está en inglés" — criterio: "0 textos de interfaz en inglés
// fuera del contenido léxico".
//
// El código propio ya estaba en español (revisión de los 619 literales de
// lib/). Lo que NO salía de ningún literal eran los textos que pone el propio
// Flutter —el tooltip del botón "Atrás", la barra de Cortar/Copiar/Pegar, la
// etiqueta de la barrera de los menús—, que sin configurar la localización
// salen en inglés en CUALQUIER dispositivo (incluso uno en español). Estas
// pruebas fijan que eso no vuelva a pasar.

Future<void> _abrirApp(
  WidgetTester tester, {
  bool dispositivoEnIngles = true,
}) async {
  if (dispositivoEnIngles) {
    // Un teléfono con el idioma en inglés (como el emulador de las pruebas
    // en vivo) no debe hacer que la interfaz salga en inglés.
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }
  await tester.pumpWidget(SpellingBeeApp(authController: AuthController()));
}

Future<void> _alturaSuficiente(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Monta [pantalla] con la MISMA configuración de idioma que la app real
/// (core/localizacion.dart) y la abre con un push desde una pantalla raíz, para
/// que tenga botón "Atrás" como en la app.
Future<void> _abrirPantalla(
  WidgetTester tester,
  Widget Function(AuthController auth) pantalla,
) async {
  final auth = AuthController();
  // Descarta cualquier app anterior de la misma prueba: si no, el Navigator
  // conserva las pantallas ya empujadas y el botón "abrir" queda tapado.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      locale: localeDeLaInterfaz,
      supportedLocales: localesSoportados,
      localizationsDelegates: delegadosDeLocalizacion,
      home: Builder(
        builder: (contexto) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(contexto).push(
                MaterialPageRoute<void>(builder: (_) => pantalla(auth)),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('el idioma de la app está fijo en español, aunque el dispositivo esté en inglés', () {
    testWidgets('el locale resuelto es es y los textos del framework vienen en español', (tester) async {
      await _abrirApp(tester);

      final contexto = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(contexto).languageCode, 'es');

      final m = MaterialLocalizations.of(contexto);
      expect(m.backButtonTooltip, 'Atrás');
      expect(m.modalBarrierDismissLabel, 'Cerrar');
      expect(m.selectAllButtonLabel, 'Seleccionar todo');
      expect(m.cutButtonLabel, 'Cortar');
      expect(m.copyButtonLabel, 'Copiar');
      expect(m.pasteButtonLabel, 'Pegar');
      expect(m.okButtonLabel.toLowerCase(), 'aceptar');
      expect(m.cancelButtonLabel.toLowerCase(), 'cancelar');
      expect(m.closeButtonLabel.toLowerCase(), 'cerrar');
      expect(m.alertDialogLabel, 'Alerta');
    });

    testWidgets('el botón Atrás de la barra superior se anuncia en español', (tester) async {
      await _abrirApp(tester);
      await tester.tap(find.text('¿Eres alumno nuevo? Crea tu cuenta'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Atrás'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    });

    testWidgets('las etiquetas de la barra de selección de texto están en español', (tester) async {
      await _abrirApp(tester);
      final contexto = tester.element(find.byType(Scaffold).first);

      String etiqueta(ContextMenuButtonType tipo) =>
          AdaptiveTextSelectionToolbar.getButtonLabel(
            contexto,
            ContextMenuButtonItem(type: tipo, onPressed: () {}),
          );

      expect(etiqueta(ContextMenuButtonType.cut), 'Cortar');
      expect(etiqueta(ContextMenuButtonType.copy), 'Copiar');
      expect(etiqueta(ContextMenuButtonType.paste), 'Pegar');
      expect(etiqueta(ContextMenuButtonType.selectAll), 'Seleccionar todo');
    });

    testWidgets('al mantener pulsado un campo de texto, la barra que aparece dice Seleccionar todo / Cortar / Copiar', (tester) async {
      await _abrirApp(tester);
      final campo = find.byType(TextFormField).first;
      await tester.enterText(campo, 'hola');
      await tester.pump();

      final editable = tester.state<EditableTextState>(
        find.descendant(of: campo, matching: find.byType(EditableText)),
      );
      expect(editable.showToolbar(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Seleccionar todo'), findsOneWidget);
      expect(find.text('Select all'), findsNothing);

      editable.selectAll(SelectionChangedCause.toolbar);
      editable.showToolbar();
      await tester.pumpAndSettle();
      expect(find.text('Cortar'), findsOneWidget);
      expect(find.text('Copiar'), findsOneWidget);
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('la barrera de un menú desplegable se anuncia como Cerrar (no Dismiss)', (tester) async {
      await _abrirApp(tester);
      await _alturaSuficiente(tester);
      await tester.tap(find.text('¿Eres alumno nuevo? Crea tu cuenta'));
      await tester.pumpAndSettle();

      // El SemanticsHandle debe liberarse antes de que termine la prueba (un
      // addTearDown llega tarde y el framework lo reporta como fuga).
      final semantica = tester.ensureSemantics();
      try {
        await tester.tap(find.text('Carrera'));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('Cerrar'), findsWidgets);
        expect(find.bySemanticsLabel('Dismiss'), findsNothing);
      } finally {
        semantica.dispose();
      }
    });
  });

  group('barrido de pantallas: ningún texto visible ni anunciado tiene palabras en inglés', () {
    testWidgets('login, inicial y con errores de validación', (tester) async {
      await _abrirApp(tester);
      await expectSoloEspanol(tester, pantalla: 'login');

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();
      expect(find.text('Escribe tu matrícula o usuario.'), findsOneWidget);
      await expectSoloEspanol(tester, pantalla: 'login con errores');
    });

    testWidgets('registro, inicial y con errores de validación', (tester) async {
      await _abrirApp(tester);
      await _alturaSuficiente(tester);
      await tester.tap(find.text('¿Eres alumno nuevo? Crea tu cuenta'));
      await tester.pumpAndSettle();
      await expectSoloEspanol(tester, pantalla: 'registro');

      // El botón "Crear cuenta" está bloqueado hasta aceptar el aviso de
      // privacidad (RF-37): se marca para que la validación muestre sus errores.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
      await tester.pump();
      expect(find.text('Elige tu carrera.'), findsOneWidget);
      await expectSoloEspanol(tester, pantalla: 'registro con errores');
    });

    testWidgets('recuperar contraseña, inicial y con error de validación', (tester) async {
      await _abrirApp(tester);
      await _alturaSuficiente(tester);
      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pumpAndSettle();
      await expectSoloEspanol(tester, pantalla: 'recuperar contraseña');

      await tester.tap(find.widgetWithText(FilledButton, 'Enviar correo de restablecimiento'));
      await tester.pump();
      expect(find.text('Este campo es obligatorio.'), findsOneWidget);
      await expectSoloEspanol(tester, pantalla: 'recuperar contraseña con error');
    });

    testWidgets('restablecer contraseña, inicial y con errores de validación', (tester) async {
      await _alturaSuficiente(tester);
      await _abrirPantalla(tester, (auth) => RestablecerPasswordScreen(authController: auth));
      await expectSoloEspanol(tester, pantalla: 'restablecer contraseña');

      await tester.tap(find.widgetWithText(FilledButton, 'Restablecer contraseña'));
      await tester.pump();
      expect(find.text('Pega el código que recibiste.'), findsOneWidget);
      await expectSoloEspanol(tester, pantalla: 'restablecer contraseña con errores');
    });

    testWidgets('cambiar contraseña (voluntario y obligatorio), inicial y con errores', (tester) async {
      await _alturaSuficiente(tester);
      await _abrirPantalla(tester, (auth) => CambiarPasswordScreen(authController: auth));
      await expectSoloEspanol(tester, pantalla: 'cambiar contraseña');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('Escribe tu contraseña actual.'), findsOneWidget);
      await expectSoloEspanol(tester, pantalla: 'cambiar contraseña con errores');

      await _abrirPantalla(tester, (auth) => CambiarPasswordScreen(authController: auth, obligatorio: true));
      expect(find.textContaining('Tu contraseña es temporal'), findsOneWidget);
      await expectSoloEspanol(tester, pantalla: 'cambiar contraseña obligatorio');
    });
  });

  group('el ayudante de detección funciona (para que un "todo en español" no sea un falso verde)', () {
    test('marca inglés típico y deja pasar español', () {
      expect(palabrasEnIngles('Back'), isNotEmpty);
      expect(palabrasEnIngles('Select all'), isNotEmpty);
      expect(palabrasEnIngles('Dismiss'), isNotEmpty);
      expect(palabrasEnIngles('File too large'), isNotEmpty);
      expect(palabrasEnIngles('property foo should not exist'), isNotEmpty);
      expect(palabrasEnIngles('Atrás'), isEmpty);
      expect(palabrasEnIngles('Ocurrió un error inesperado. Intenta de nuevo más tarde.'), isEmpty);
      expect(palabrasEnIngles('Usuario o contraseña incorrectos.'), isEmpty);
    });

    test('no marca español legítimo que se parece a una palabra inglesa', () {
      // "todo" (todo/all), "has" (haber), "demo" y "test" también son español.
      expect(palabrasEnIngles('Seleccionar todo'), isEmpty);
      expect(palabrasEnIngles('Has completado el nivel'), isEmpty);
      expect(palabrasEnIngles('Versión demo'), isEmpty);
      expect(palabrasEnIngles('Todo listo'), isEmpty);
    });

    test('sí marca los marcadores de desarrollo escritos como TODO/FIXME', () {
      expect(palabrasEnIngles('TODO: traducir'), ['todo']);
      expect(palabrasEnIngles('FIXME'), ['fixme']);
    });

    test('permite el contenido léxico y el nombre del producto, y nada más', () {
      expect(palabrasEnIngles('This is my business.', contenidoIngles: ['This is my business.']), isEmpty);
      expect(palabrasEnIngles('Spelling Bee'), isEmpty);
      expect(palabrasEnIngles('This is my business. Cancel', contenidoIngles: ['This is my business.']), ['cancel']);
    });
  });

  group('textos de relleno de desarrollo', () {
    test('el nombre de la app en Android es el del producto, no el identificador técnico', () {
      final manifiesto = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifiesto, contains('android:label="Spelling Bee"'));
      expect(manifiesto, isNot(contains('android:label="spelling_bee"')));
    });

    test('pubspec.yaml no conserva la descripción de plantilla de "flutter create"', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('A new Flutter project')));
    });
  });

  group('guardia de código fuente: ningún literal de lib/ tiene palabras en inglés', () {
    test('el extractor de literales funciona', () {
      final literales = literalesDeDart("final a = Text('Cancel'); // 'comentario'\nfinal b = \"Guardar \${x} ya\";");
      expect(literales.map((l) => l.texto.trim()), ['Cancel', 'Guardar   ya']);
    });

    test('recorre toda la app y encuentra los literales conocidos', () {
      final todos = _literalesDeLaApp();
      expect(todos.length, greaterThan(400));
      expect(todos.any((l) => l.literal.texto == 'Iniciar sesión'), isTrue);
    });

    test('no hay palabras en inglés en ningún texto del código (fuera de códigos técnicos)', () {
      final ofensas = <String>[];
      for (final (archivo, lit) in _literalesDeLaApp().map((e) => (e.archivo, e.literal))) {
        // Se omiten los literales técnicos que nunca se ven: directivas
        // import/export, códigos en MAYÚSCULAS ('SIN_CONEXION') y rutas de la
        // API ('/auth/login').
        if (lit.esDirectiva ||
            RegExp(r'^[A-Z0-9_ ]+$').hasMatch(lit.texto) ||
            RegExp(r'^/[A-Za-z0-9_\-/ ]*$').hasMatch(lit.texto)) {
          continue;
        }
        final ingles = palabrasEnIngles(lit.texto);
        if (ingles.isNotEmpty) {
          ofensas.add('$archivo:${lit.linea} «${lit.texto}» [${ingles.join(", ")}]');
        }
      }
      expect(ofensas, isEmpty, reason: ofensas.join('\n'));
    });
  });
}

// ---------------------------------------------------------------------------
// Extractor de literales de cadena de Dart (ignora comentarios, une nada:
// cada literal se revisa por separado; las interpolaciones se reemplazan por
// un espacio porque no son texto visible por sí solas).
// ---------------------------------------------------------------------------

class LiteralDeDart {
  const LiteralDeDart(this.texto, this.linea, this.esDirectiva);
  final String texto;
  final int linea;
  final bool esDirectiva;
}

List<({String archivo, LiteralDeDart literal})> _literalesDeLaApp() {
  final resultado = <({String archivo, LiteralDeDart literal})>[];
  final archivos = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final archivo in archivos) {
    for (final lit in literalesDeDart(archivo.readAsStringSync())) {
      resultado.add((archivo: archivo.path.replaceAll('\\', '/'), literal: lit));
    }
  }
  return resultado;
}

(String, int) _leerCadena(String src, int ini) {
  var j = ini;
  var raw = false;
  if (src[j] == 'r' && j + 1 < src.length && (src[j + 1] == "'" || src[j + 1] == '"')) {
    raw = true;
    j++;
  }
  final q = src[j];
  final triple = j + 2 < src.length && src[j + 1] == q && src[j + 2] == q;
  j += triple ? 3 : 1;
  final salida = StringBuffer();
  final letra = RegExp(r'[A-Za-z_]');
  final letraODigito = RegExp(r'[A-Za-z0-9_]');
  while (j < src.length) {
    final c = src[j];
    final cierra = triple
        ? (c == q && j + 2 < src.length && src[j + 1] == q && src[j + 2] == q)
        : c == q;
    if (cierra) return (salida.toString(), j + (triple ? 3 : 1));
    if (!raw && c == '\\' && j + 1 < src.length) {
      salida.write(src[j + 1]);
      j += 2;
      continue;
    }
    if (!raw && c == r'$' && j + 1 < src.length) {
      if (src[j + 1] == '{') {
        var k = j + 2;
        var profundidad = 1;
        while (k < src.length && profundidad > 0) {
          final ch = src[k];
          if (ch == '{') {
            profundidad++;
          } else if (ch == '}') {
            profundidad--;
          } else if (ch == "'" || ch == '"') {
            k = _leerCadena(src, k).$2;
            continue;
          }
          k++;
        }
        salida.write(' ');
        j = k;
        continue;
      }
      if (letra.hasMatch(src[j + 1])) {
        var k = j + 1;
        while (k < src.length && letraODigito.hasMatch(src[k])) {
          k++;
        }
        salida.write(' ');
        j = k;
        continue;
      }
    }
    salida.write(c);
    j++;
  }
  return (salida.toString(), j);
}

List<LiteralDeDart> literalesDeDart(String src) {
  final literales = <LiteralDeDart>[];
  var i = 0;
  var linea = 1;
  while (i < src.length) {
    final c = src[i];
    if (c == '\n') {
      linea++;
      i++;
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      var profundidad = 1;
      i += 2;
      while (i < src.length && profundidad > 0) {
        if (src[i] == '\n') linea++;
        if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
          profundidad++;
          i += 2;
        } else if (src[i] == '*' && i + 1 < src.length && src[i + 1] == '/') {
          profundidad--;
          i += 2;
        } else {
          i++;
        }
      }
      continue;
    }
    final empiezaRaw = c == 'r' &&
        i + 1 < src.length &&
        (src[i + 1] == "'" || src[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_]').hasMatch(src[i - 1]));
    if (c == "'" || c == '"' || empiezaRaw) {
      final inicioLinea = src.lastIndexOf('\n', i - 1) + 1;
      final antes = src.substring(inicioLinea, i).trim();
      final (texto, fin) = _leerCadena(src, i);
      literales.add(LiteralDeDart(texto, linea, RegExp(r'^(import|export|part)\b').hasMatch(antes)));
      linea += '\n'.allMatches(src.substring(i, fin)).length;
      i = fin;
      continue;
    }
    i++;
  }
  return literales;
}

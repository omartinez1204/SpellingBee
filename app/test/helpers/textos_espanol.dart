import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// RNF-01 (T-071): "0 textos de interfaz en inglés fuera del contenido léxico".
// Este ayudante convierte esa revisión en una comprobación automática sobre lo
// que REALMENTE se dibuja: recolecta cada texto visible y cada texto que un
// lector de pantalla anuncia (etiquetas, pistas, tooltips, valores) — incluidos
// los que pone el propio Flutter, que son los que no salen de ningún literal
// del código — y falla si alguno contiene palabras inglesas.
//
// Es una heurística, no una prueba de idioma: detecta vocabulario inglés típico
// de interfaz, de mensajes por defecto de librerías y de plantillas de
// desarrollo. La revisión completa del código fuente se hizo a mano (T-071);
// esto evita que un texto así vuelva a colarse sin que nadie lo note.

/// Palabras que delatan un texto en inglés. Se excluyen a propósito las que
/// también son español ("error", "total", "audio", "token", "id", "no"...).
const _palabrasInglesas = <String>{
  // Vocabulario típico de interfaz y de mensajes por defecto del framework.
  'back', 'next', 'previous', 'cancel', 'save', 'delete', 'remove', 'edit',
  'add', 'close', 'open', 'done', 'apply', 'reset', 'clear', 'search', 'share',
  'copy', 'cut', 'paste', 'select', 'dismiss', 'alert', 'menu', 'show', 'hide',
  'more', 'less', 'loading', 'retry', 'submit', 'send', 'login', 'logout',
  'signin', 'signup', 'password', 'username', 'email', 'welcome', 'hello',
  'world', 'home', 'settings', 'profile', 'page', 'yes', 'please', 'sorry',
  'online', 'offline', 'sync', 'synced',
  // Palabras funcionales del inglés que no existen en español.
  'the', 'and', 'you', 'your', 'with', 'this', 'that', 'from', 'for', 'are',
  'was', 'were', 'have', 'will', 'must', 'should', 'not', 'be', 'been', 'into',
  'of', 'to',
  // Mensajes típicos de librerías (class-validator, multer, Nest...).
  'unexpected', 'invalid', 'unauthorized', 'forbidden', 'failed', 'required',
  'missing', 'empty', 'large', 'field', 'file', 'string', 'number', 'integer',
  'array', 'property', 'exist', 'valid',
  // Restos de plantilla o de desarrollo.
  'lorem', 'ipsum', 'placeholder', 'backlog', 'testing', 'pushed', 'button',
  'times', 'project',
  // Términos del dominio que deben ir en español.
  'level', 'word', 'score', 'streak', 'badge', 'student', 'teacher',
  'professor', 'course', 'recording', 'listen', 'spell',
};

// Palabras que SOLO delatan inglés escritas tal cual, en mayúsculas: en
// minúsculas también son español ("Seleccionar todo", "Has completado...").
const _marcadoresEnMayusculas = <String>{'TODO', 'FIXME'};

/// Nombre propio del producto (el ERS lo llama "Spelling Bee"): no se traduce.
const nombreDelProducto = 'Spelling Bee';

/// Palabras inglesas (de la lista) que aparecen en [texto], una vez quitado el
/// nombre del producto y el contenido léxico permitido (la palabra a practicar
/// y su oración de ejemplo).
List<String> palabrasEnIngles(
  String texto, {
  Iterable<String> contenidoIngles = const [],
}) {
  var limpio = texto.replaceAll(nombreDelProducto, ' ');
  // Primero lo más largo: la oración "This is my business." debe quitarse
  // completa antes que la palabra "business", que también está dentro de ella.
  final permitidos = contenidoIngles.where((p) => p.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final permitido in permitidos) {
    limpio = limpio.replaceAll(permitido, ' ');
  }
  return [
    for (final m in RegExp(r'\p{L}+', unicode: true).allMatches(limpio))
      if (_palabrasInglesas.contains(m.group(0)!.toLowerCase()) ||
          _marcadoresEnMayusculas.contains(m.group(0)!))
        m.group(0)!.toLowerCase(),
  ];
}

/// Todos los textos de la pantalla actual: los `Text` dibujados, los tooltips y
/// todo lo que el árbol de semántica (lo que lee TalkBack) anuncia.
Future<Set<String>> textosDePantalla(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final textos = <String>{};

    for (final texto in tester.widgetList<Text>(find.byType(Text))) {
      final valor = texto.data ?? texto.textSpan?.toPlainText();
      if (valor != null && valor.trim().isNotEmpty) textos.add(valor);
    }
    for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
      final mensaje = tooltip.message;
      if (mensaje != null && mensaje.isNotEmpty) textos.add(mensaje);
    }

    void visitar(SemanticsNode nodo) {
      final datos = nodo.getSemanticsData();
      for (final s in [
        datos.label,
        datos.hint,
        datos.value,
        datos.tooltip,
        datos.increasedValue,
        datos.decreasedValue,
      ]) {
        if (s.trim().isNotEmpty) textos.add(s);
      }
      nodo.visitChildren((hijo) {
        visitar(hijo);
        return true;
      });
    }

    final raiz = tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
    if (raiz != null) visitar(raiz);
    return textos;
  } finally {
    handle.dispose();
  }
}

/// Falla si algún texto de la pantalla actual contiene palabras inglesas.
/// [contenidoIngles] es lo único permitido en inglés: la palabra practicada y
/// su oración de ejemplo (y, si hace falta, la oración que escribió el alumno).
Future<void> expectSoloEspanol(
  WidgetTester tester, {
  Iterable<String> contenidoIngles = const [],
  String pantalla = 'la pantalla',
}) async {
  final textos = await textosDePantalla(tester);
  expect(
    textos,
    isNotEmpty,
    reason: 'no se recolectó ningún texto en $pantalla: el recolector no funciona',
  );
  final ingles = <String, List<String>>{
    for (final t in textos)
      if (palabrasEnIngles(t, contenidoIngles: contenidoIngles).isNotEmpty)
        t: palabrasEnIngles(t, contenidoIngles: contenidoIngles),
  };
  expect(
    ingles,
    isEmpty,
    reason:
        'textos con palabras en inglés en $pantalla (RNF-01): '
        '${ingles.entries.map((e) => '«${e.key}» [${e.value.join(", ")}]').join(' | ')}',
  );
}

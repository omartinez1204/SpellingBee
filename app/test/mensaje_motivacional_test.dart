import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/mensaje_motivacional.dart';

// RF-22: la lógica de qué mensaje corresponde (bienvenida/mejora/empate/no
// mejora) es pura — no depende de la pantalla ni de la llamada de red que
// trae mejorPrevioSegundos (eso se prueba aparte, en
// practica_palabra_screen_test.dart) — mismo motivo que posicionTrasSalto
// (T-031) y formatearTiempo (T-032) viven aparte de sus pantallas.
void main() {
  group('construirMensajeMotivacional (RF-22)', () {
    test('sin tiempo previo (primera vez), da un mensaje de bienvenida, no una comparación', () {
      final mensaje = construirMensajeMotivacional(
        actualSegundos: 45,
        mejorPrevioSegundos: null,
      );

      expect(mensaje, contains('primer intento'));
      // No debe intentar mencionar un tiempo previo inexistente.
      expect(mensaje, isNot(contains('mejor tiempo')));
    });

    test('tiempo actual MENOR al previo: mensaje de mejora, con el tiempo previo en mm:ss', () {
      final mensaje = construirMensajeMotivacional(
        actualSegundos: 20,
        mejorPrevioSegundos: 45,
      );

      expect(mensaje, contains('Mejoraste'));
      expect(mensaje, contains('00:45'));
    });

    test('tiempo actual IGUAL al previo: mensaje de empate, con el tiempo en mm:ss', () {
      final mensaje = construirMensajeMotivacional(
        actualSegundos: 45,
        mejorPrevioSegundos: 45,
      );

      expect(mensaje, contains('Igualaste'));
      expect(mensaje, contains('00:45'));
    });

    test(
      'tiempo actual MAYOR al previo: no supera la marca, pero el mensaje sigue siendo positivo (sin "error"/"mal"/negativo)',
      () {
        final mensaje = construirMensajeMotivacional(
          actualSegundos: 60,
          mejorPrevioSegundos: 45,
        );

        expect(mensaje, contains('00:45'));
        expect(mensaje, contains('sigue practicando'));
        for (final palabraNegativa in ['error', 'mal', 'perdiste', 'fallaste']) {
          expect(
            mensaje.toLowerCase(),
            isNot(contains(palabraNegativa)),
            reason: 'el ERS pide refuerzos positivos, nunca mensajes negativos',
          );
        }
      },
    );
  });
}

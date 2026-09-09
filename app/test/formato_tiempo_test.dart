import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/formato_tiempo.dart';

// RF-18: el ERS da el formato como ejemplo literal ("00:03 / 00:12") — estas
// pruebas verifican la mitad de ese formato (mm:ss de un solo Duration);
// PracticaPalabraScreen arma el "algo / algo" completo.
void main() {
  group('formatearTiempo (RF-18)', () {
    test('cero se muestra como 00:00', () {
      expect(formatearTiempo(Duration.zero), '00:00');
    });

    test('segundos sueltos se rellenan con cero a la izquierda', () {
      expect(formatearTiempo(const Duration(seconds: 3)), '00:03');
    });

    test('exactamente el ejemplo del ERS: 12 segundos', () {
      expect(formatearTiempo(const Duration(seconds: 12)), '00:12');
    });

    test('minutos y segundos combinados', () {
      expect(formatearTiempo(const Duration(minutes: 1, seconds: 5)), '01:05');
    });

    test('los milisegundos no se redondean hacia arriba', () {
      expect(
        formatearTiempo(const Duration(seconds: 3, milliseconds: 999)),
        '00:03',
      );
    });

    test('más de 59 segundos avanza el minuto', () {
      expect(formatearTiempo(const Duration(seconds: 60)), '01:00');
    });

    test('más de 9 minutos no se trunca (dos dígitos como mínimo, no como máximo)', () {
      expect(formatearTiempo(const Duration(minutes: 10, seconds: 30)), '10:30');
    });
  });
}

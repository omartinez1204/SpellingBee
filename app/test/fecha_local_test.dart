import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/fecha_local.dart';

// RF-23 (T-046): la racha se calcula con la fecha calendario LOCAL DEL
// DISPOSITIVO — estas pruebas verifican el formato "YYYY-MM-DD" que se
// manda al backend, no la lógica de racha en sí (eso vive en el backend,
// probado en backend/test/racha.e2e-spec.ts).
void main() {
  group('formatearFechaLocal (RF-23)', () {
    test('rellena mes y día con cero a la izquierda', () {
      expect(formatearFechaLocal(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('mes y día de dos dígitos se mantienen tal cual', () {
      expect(formatearFechaLocal(DateTime(2026, 12, 25)), '2026-12-25');
    });

    test('usa año/mes/día locales, no la hora ni los segundos', () {
      expect(
        formatearFechaLocal(DateTime(2026, 9, 10, 23, 59, 59)),
        '2026-09-10',
      );
    });

    test('justo después de medianoche ya es el día siguiente', () {
      expect(
        formatearFechaLocal(DateTime(2026, 9, 11, 0, 0, 1)),
        '2026-09-11',
      );
    });
  });
}

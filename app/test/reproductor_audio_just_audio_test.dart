import 'package:flutter_test/flutter_test.dart';
import 'package:spelling_bee/core/reproductor_audio_just_audio.dart';

// posicionTrasSalto() es la parte de retroceder()/adelantar() (T-031,
// RF-14/RF-15) que sí se puede probar sin AudioPlayer real: es una función
// pura, separada a propósito de ReproductorAudioJustAudio para no depender
// de un canal de plataforma de audio (que no existe bajo `flutter test`).
// La verificación de que retroceder()/adelantar() en verdad llaman a esta
// función con la posición/duración correctas del reproductor real se hizo
// a mano en dispositivo, no aquí.
void main() {
  group('posicionTrasSalto (RF-14/RF-15)', () {
    test('retroceder 5s en medio de la pista resta exactamente 5s', () {
      final resultado = posicionTrasSalto(
        actual: const Duration(seconds: 10),
        delta: const Duration(seconds: -5),
        duracion: const Duration(seconds: 60),
      );
      expect(resultado, const Duration(seconds: 5));
    });

    test('adelantar 5s en medio de la pista suma exactamente 5s', () {
      final resultado = posicionTrasSalto(
        actual: const Duration(seconds: 10),
        delta: const Duration(seconds: 5),
        duracion: const Duration(seconds: 60),
      );
      expect(resultado, const Duration(seconds: 15));
    });

    test(
      'RF-14: retroceder cerca del inicio no pasa del segundo 0 (no da negativo)',
      () {
        final resultado = posicionTrasSalto(
          actual: const Duration(seconds: 3),
          delta: const Duration(seconds: -5),
          duracion: const Duration(seconds: 60),
        );
        expect(resultado, Duration.zero);
      },
    );

    test('RF-14: retroceder ya en el segundo 0 se queda en 0', () {
      final resultado = posicionTrasSalto(
        actual: Duration.zero,
        delta: const Duration(seconds: -5),
        duracion: const Duration(seconds: 60),
      );
      expect(resultado, Duration.zero);
    });

    test(
      'RF-15: adelantar cerca del final no excede la duración total',
      () {
        final resultado = posicionTrasSalto(
          actual: const Duration(seconds: 58),
          delta: const Duration(seconds: 5),
          duracion: const Duration(seconds: 60),
        );
        expect(resultado, const Duration(seconds: 60));
      },
    );

    test('RF-15: adelantar ya en la duración total se queda ahí', () {
      final resultado = posicionTrasSalto(
        actual: const Duration(seconds: 60),
        delta: const Duration(seconds: 5),
        duracion: const Duration(seconds: 60),
      );
      expect(resultado, const Duration(seconds: 60));
    });

    test(
      'sin duración conocida todavía, adelantar no se topa con ningún límite superior',
      () {
        final resultado = posicionTrasSalto(
          actual: const Duration(seconds: 10),
          delta: const Duration(seconds: 5),
          duracion: null,
        );
        expect(resultado, const Duration(seconds: 15));
      },
    );
  });
}

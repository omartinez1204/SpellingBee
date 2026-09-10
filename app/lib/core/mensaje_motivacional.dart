import 'formato_tiempo.dart';

/// RF-22 (T-042): mensaje motivacional al terminar la práctica de una
/// palabra. Aparte para poder probar las 4 combinaciones (bienvenida/
/// mejora/empate/no-mejora) como función pura, sin pantalla ni red de por
/// medio — mismo motivo que posicionTrasSalto (T-031) y formatearTiempo
/// (T-032).
///
/// Ninguna variante usa tono negativo ni de "error" — ver
/// docs/diseno-tecnico.md: "usar refuerzos positivos breves... en lugar de
/// mensajes negativos" — ni siquiera cuando el alumno no superó su marca.
String construirMensajeMotivacional({
  required int actualSegundos,
  required int? mejorPrevioSegundos,
}) {
  if (mejorPrevioSegundos == null) {
    return '¡Felicidades por completar tu primer intento con esta palabra!';
  }

  final mejorFormateado = formatearTiempo(
    Duration(seconds: mejorPrevioSegundos),
  );
  if (actualSegundos < mejorPrevioSegundos) {
    return '¡Mejoraste tu marca! Tu mejor tiempo anterior era $mejorFormateado.';
  }
  if (actualSegundos == mejorPrevioSegundos) {
    return '¡Igualaste tu mejor tiempo ($mejorFormateado)!';
  }
  return 'Tu mejor tiempo sigue siendo $mejorFormateado — ¡sigue practicando para superarlo!';
}

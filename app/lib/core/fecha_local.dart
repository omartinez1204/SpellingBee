// RF-23 (T-046): "un día" se define por la fecha calendario LOCAL DEL
// DISPOSITIVO del alumno, nunca la del servidor. Formatea solo la parte de
// fecha de un DateTime — año/mes/día tal como los expone el propio
// DateTime, SIN pasar por .toUtc() en ningún punto de la llamada: eso
// cambiaría la fecha calendario cerca de medianoche según la zona horaria
// del dispositivo, justo lo que RF-23 pide evitar. Función pura, sin nada
// de Flutter de por medio — mismo motivo que formato_tiempo.dart.
String formatearFechaLocal(DateTime fecha) {
  final anio = fecha.year.toString().padLeft(4, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  final dia = fecha.day.toString().padLeft(2, '0');
  return '$anio-$mes-$dia';
}

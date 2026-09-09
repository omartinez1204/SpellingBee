// RF-18: formato mm:ss, ej. "00:03". Aparte para poder probarla sola —
// es una función pura, sin nada de Flutter ni de just_audio de por medio.
String formatearTiempo(Duration d) {
  final totalSegundos = d.inSeconds;
  final minutos = totalSegundos ~/ 60;
  final segundos = totalSegundos % 60;
  return '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}';
}

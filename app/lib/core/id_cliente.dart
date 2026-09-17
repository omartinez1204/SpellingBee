import 'dart:math';

/// Identificador generado en el cliente (RF-33, docs/diseno-tecnico.md §3.6):
/// cada registro de práctica pendiente de sincronizar lleva uno, para que el
/// futuro POST /practica/sync (T-063) pueda deduplicar si un reintento
/// reenvía un registro que el servidor ya había recibido. UUID v4 estándar,
/// generado con dart:math (Random.secure()) sin depender de un paquete
/// externo — no hace falta más que "irrepetible en la práctica", no un
/// generador certificado.
String generarIdCliente() {
  final aleatorio = Random.secure();
  final bytes = List<int>.generate(16, (_) => aleatorio.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versión 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122

  String hex(int inicio, int fin) => bytes
      .sublist(inicio, fin)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

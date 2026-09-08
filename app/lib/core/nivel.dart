/// Respuesta de GET /niveles (T-020).
class Nivel {
  const Nivel({required this.id, required this.nombre, required this.orden});

  factory Nivel.desdeJson(Map<String, dynamic> json) {
    return Nivel(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      orden: json['orden'] as int,
    );
  }

  final int id;
  final String nombre;
  final int orden;
}

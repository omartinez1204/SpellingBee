/// RF-24 (T-047): insignia permanente de un nivel completado al 100%.
class Insignia {
  const Insignia({
    required this.idNivel,
    required this.nombreNivel,
    required this.fechaOtorgada,
  });

  factory Insignia.desdeJson(Map<String, dynamic> json) => Insignia(
    idNivel: json['id_nivel'] as int,
    nombreNivel: json['nombre_nivel'] as String,
    fechaOtorgada: DateTime.parse(json['fecha_otorgada'] as String),
  );

  final int idNivel;
  final String nombreNivel;
  final DateTime fechaOtorgada;
}

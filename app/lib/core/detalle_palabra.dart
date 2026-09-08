/// Respuesta de GET /palabras/:id (T-023, backend/src/palabras/palabras.service.ts).
/// Los 4 campos siempre vienen, completos o no — ocultar significado/oración
/// hasta que el alumno pida la pista es responsabilidad de esta app, no del
/// backend.
class DetallePalabra {
  const DetallePalabra({
    required this.id,
    required this.texto,
    required this.significadoEs,
    required this.oracionEjemplo,
    required this.urlAudio,
  });

  factory DetallePalabra.desdeJson(Map<String, dynamic> json) {
    return DetallePalabra(
      id: json['id'] as int,
      texto: json['texto'] as String,
      significadoEs: json['significado_es'] as String?,
      oracionEjemplo: json['oracion_ejemplo'] as String?,
      urlAudio: json['url_audio'] as String?,
    );
  }

  final int id;
  final String texto;
  final String? significadoEs;
  final String? oracionEjemplo;
  final String? urlAudio;
}

import 'detalle_palabra.dart';
import 'nivel.dart';

/// Respuesta de GET /niveles/:id/descarga (T-060, RF-31): el paquete
/// completo de un nivel para descargar y usar sin conexión (RF-32). Cada
/// palabra trae el mismo detalle completo que GET /palabras/:id (T-023) —
/// de ahí que se reutilice DetallePalabra en vez de un modelo aparte.
class PaqueteNivel {
  const PaqueteNivel({required this.nivel, required this.palabras});

  factory PaqueteNivel.desdeJson(Map<String, dynamic> json) {
    return PaqueteNivel(
      nivel: Nivel.desdeJson(json['nivel'] as Map<String, dynamic>),
      palabras: (json['palabras'] as List<dynamic>)
          .map(
            (item) => DetallePalabra.desdeJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final Nivel nivel;
  final List<DetallePalabra> palabras;

  /// Usado por AlmacenPaquetes para guardar en disco (T-061) — mismas
  /// claves snake_case que ya entiende DetallePalabra.desdeJson(), para leer
  /// de vuelta con ese mismo constructor sin duplicar el mapeo de campos.
  Map<String, dynamic> aJson() => {
    'nivel': {'id': nivel.id, 'nombre': nivel.nombre, 'orden': nivel.orden},
    'palabras': palabras
        .map(
          (palabra) => {
            'id': palabra.id,
            'texto': palabra.texto,
            'significado_es': palabra.significadoEs,
            'oracion_ejemplo': palabra.oracionEjemplo,
            'url_audio': palabra.urlAudio,
          },
        )
        .toList(),
  };
}

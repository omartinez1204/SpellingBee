/// Un registro de práctica generado SIN CONEXIÓN, pendiente de enviar al
/// backend (RF-33, T-062). Mismos 4 campos que POST /practica (T-045) más un
/// `id` generado en el cliente (ver id_cliente.dart) que el futuro
/// POST /practica/sync (T-063) usará como llave de deduplicación — un
/// reintento nunca debe duplicar un registro que el servidor ya recibió
/// (docs/diseno-tecnico.md §3.6).
class RegistroPracticaPendiente {
  const RegistroPracticaPendiente({
    required this.id,
    required this.idPalabra,
    required this.tiempoSegundos,
    required this.oracionAlumno,
    required this.deletreoCorrecto,
    required this.fechaLocal,
  });

  factory RegistroPracticaPendiente.desdeJson(Map<String, dynamic> json) {
    return RegistroPracticaPendiente(
      id: json['id'] as String,
      idPalabra: json['id_palabra'] as int,
      tiempoSegundos: json['tiempo_segundos'] as int,
      oracionAlumno: json['oracion_alumno'] as String,
      deletreoCorrecto: json['deletreo_correcto'] as bool,
      fechaLocal: json['fecha_local'] as String,
    );
  }

  final String id;
  final int idPalabra;
  final int tiempoSegundos;
  final String oracionAlumno;
  final bool deletreoCorrecto;

  /// Ya formateada como 'YYYY-MM-DD' (ver fecha_local.dart), capturada una
  /// sola vez en el momento de terminar la práctica — no se recalcula aquí
  /// ni al sincronizar después, por el mismo motivo que PracticaService.
  /// guardarPractica() nunca recibe un DateTime crudo tan lejos de dónde se
  /// capturó (RF-23: la fecha calendario local del INSTANTE de terminar).
  final String fechaLocal;

  Map<String, dynamic> aJson() => {
    'id': id,
    'id_palabra': idPalabra,
    'tiempo_segundos': tiempoSegundos,
    'oracion_alumno': oracionAlumno,
    'deletreo_correcto': deletreoCorrecto,
    'fecha_local': fechaLocal,
  };
}

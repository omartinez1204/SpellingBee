/// Una fila de GET /admin/alumnos/:id (T-051, RF-29): un intento real de
/// práctica, sin deduplicar (a diferencia de AvanceNivel) — si el alumno
/// practicó la misma palabra varias veces, aparece una fila por cada una.
/// Deliberadamente sin deletreo_correcto: el propio ERS solo pide palabra,
/// tiempo y oración para esta tabla.
class IntentoPractica {
  const IntentoPractica({
    required this.idPalabra,
    required this.palabra,
    required this.tiempoSegundos,
    required this.oracionAlumno,
  });

  factory IntentoPractica.desdeJson(Map<String, dynamic> json) {
    return IntentoPractica(
      idPalabra: json['id_palabra'] as int,
      palabra: json['palabra'] as String,
      tiempoSegundos: json['tiempo_segundos'] as int,
      oracionAlumno: json['oracion_alumno'] as String,
    );
  }

  final int idPalabra;
  final String palabra;
  final int tiempoSegundos;
  final String oracionAlumno;
}

/// Respuesta paginada de GET /admin/alumnos/:id (RNF-12).
class DetalleAlumno {
  const DetalleAlumno({
    required this.intentos,
    required this.total,
    required this.pagina,
    required this.totalPaginas,
  });

  factory DetalleAlumno.desdeJson(Map<String, dynamic> json) {
    return DetalleAlumno(
      intentos: (json['intentos'] as List<dynamic>)
          .map((item) => IntentoPractica.desdeJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      pagina: json['pagina'] as int,
      totalPaginas: json['total_paginas'] as int,
    );
  }

  final List<IntentoPractica> intentos;
  final int total;
  final int pagina;
  final int totalPaginas;
}

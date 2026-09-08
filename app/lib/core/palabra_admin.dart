/// Una fila de GET /admin/palabras o la respuesta de crear/editar/ocultar/
/// subir audio (T-024/T-025) — a diferencia de DetallePalabra (T-023, vista
/// alumno), trae también el estado completa/oculta que necesita el panel
/// docente (RF-39).
class PalabraAdmin {
  const PalabraAdmin({
    required this.id,
    required this.texto,
    required this.idNivel,
    required this.significadoEs,
    required this.oracionEjemplo,
    required this.urlAudio,
    required this.completa,
    required this.oculta,
  });

  factory PalabraAdmin.desdeJson(Map<String, dynamic> json) {
    return PalabraAdmin(
      id: json['id'] as int,
      texto: json['texto'] as String,
      idNivel: json['id_nivel'] as int,
      significadoEs: json['significado_es'] as String?,
      oracionEjemplo: json['oracion_ejemplo'] as String?,
      urlAudio: json['url_audio'] as String?,
      completa: json['completa'] as bool,
      oculta: json['oculta'] as bool,
    );
  }

  final int id;
  final String texto;
  final int idNivel;
  final String? significadoEs;
  final String? oracionEjemplo;
  final String? urlAudio;
  final bool completa;
  final bool oculta;
}

/// Respuesta paginada de GET /admin/palabras (RNF-12).
class ListaPalabrasAdmin {
  const ListaPalabrasAdmin({
    required this.palabras,
    required this.total,
    required this.pagina,
    required this.totalPaginas,
  });

  factory ListaPalabrasAdmin.desdeJson(Map<String, dynamic> json) {
    return ListaPalabrasAdmin(
      palabras: (json['palabras'] as List<dynamic>)
          .map((item) => PalabraAdmin.desdeJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      pagina: json['pagina'] as int,
      totalPaginas: json['total_paginas'] as int,
    );
  }

  final List<PalabraAdmin> palabras;
  final int total;
  final int pagina;
  final int totalPaginas;
}

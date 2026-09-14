/// Una fila del arreglo "avance" de GET /admin/alumnos (RF-28/RF-30, T-050):
/// cuántas palabras distintas de un nivel ha practicado el alumno. Cuando el
/// panel filtra por nivel (T-052), este arreglo trae solo esa entrada en vez
/// de las 3 — ver AdminAlumnosService (backend) para el porqué.
class AvanceNivel {
  const AvanceNivel({required this.idNivel, required this.palabrasPracticadas});

  factory AvanceNivel.desdeJson(Map<String, dynamic> json) {
    return AvanceNivel(
      idNivel: json['id_nivel'] as int,
      palabrasPracticadas: json['palabras_practicadas'] as int,
    );
  }

  final int idNivel;
  final int palabrasPracticadas;
}

/// Una fila de GET /admin/alumnos (T-050, RF-28).
class AlumnoConAvance {
  const AlumnoConAvance({
    required this.id,
    required this.matricula,
    required this.nombre,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.carrera,
    required this.semestre,
    required this.avance,
  });

  factory AlumnoConAvance.desdeJson(Map<String, dynamic> json) {
    return AlumnoConAvance(
      id: json['id'] as int,
      matricula: json['matricula'] as String,
      nombre: json['nombre'] as String,
      apellidoPaterno: json['apellido_paterno'] as String,
      apellidoMaterno: json['apellido_materno'] as String,
      carrera: json['carrera'] as String,
      semestre: json['semestre'] as int,
      avance: (json['avance'] as List<dynamic>)
          .map((item) => AvanceNivel.desdeJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final int id;
  final String matricula;
  final String nombre;
  final String apellidoPaterno;
  final String apellidoMaterno;
  final String carrera;
  final int semestre;
  final List<AvanceNivel> avance;

  String get nombreCompleto => '$nombre $apellidoPaterno $apellidoMaterno';
}

/// Respuesta paginada de GET /admin/alumnos (RNF-12).
class ListaAlumnos {
  const ListaAlumnos({
    required this.alumnos,
    required this.total,
    required this.pagina,
    required this.totalPaginas,
  });

  factory ListaAlumnos.desdeJson(Map<String, dynamic> json) {
    return ListaAlumnos(
      alumnos: (json['alumnos'] as List<dynamic>)
          .map((item) => AlumnoConAvance.desdeJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      pagina: json['pagina'] as int,
      totalPaginas: json['total_paginas'] as int,
    );
  }

  final List<AlumnoConAvance> alumnos;
  final int total;
  final int pagina;
  final int totalPaginas;
}

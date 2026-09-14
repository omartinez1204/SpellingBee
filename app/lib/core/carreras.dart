/// RF-01: los 3 nombres de carrera son el texto literal del ERS (no la forma
/// abreviada que trae diseno-tecnico.md §2 — ver
/// backend/src/common/carreras.ts, la misma lista del lado del servidor).
/// Compartida entre el registro de alumno (T-010) y los filtros del panel
/// docente (T-053, RF-30) para no duplicarla en dos archivos.
const carreras = [
  'Ingeniería en Agroalimentos',
  'Ingeniería en Desarrollo de Software',
  'Licenciatura en MiPymes',
];

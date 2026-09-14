// RF-01/RF-37. Texto literal del ERS (no la forma abreviada que trae
// diseno-tecnico.md §2, que transcribió mal estos 3 valores). Compartido
// entre RegistroAlumnoDto (T-011) y los filtros de progreso (T-052, RF-30)
// para que ambos validen contra exactamente el mismo enum, sin duplicarlo.
export const CARRERAS = [
  'Ingeniería en Agroalimentos',
  'Ingeniería en Desarrollo de Software',
  'Licenciatura en MiPymes',
] as const;

export type Carrera = (typeof CARRERAS)[number];

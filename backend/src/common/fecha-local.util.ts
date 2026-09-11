// RF-23: "un día" se define por la fecha calendario LOCAL DEL DISPOSITIVO
// del alumno, nunca la del servidor — el backend no tiene forma de conocer
// la zona horaria de un dispositivo a partir de un timestamp, así que el
// cliente manda la fecha ya resuelta como "YYYY-MM-DD" (sin hora, sin
// offset de zona) y el servidor la trata como una llave de calendario
// pura, nunca como un instante. Toda la aritmética aquí usa Date.UTC para
// anclar esa llave a medianoche UTC — así ninguna diferencia de zona
// horaria del propio SERVIDOR puede colarse en la resta de días.

const PATRON_FECHA_LOCAL = /^(\d{4})-(\d{2})-(\d{2})$/;
const MS_POR_DIA = 24 * 60 * 60 * 1000;

/**
 * Parsea "YYYY-MM-DD" a un Date anclado a medianoche UTC. Regresa null si
 * el formato no coincide o si la fecha no existe de verdad (p. ej.
 * "2026-02-30": Date.UTC la "normaliza" en vez de fallar, así que hay que
 * verificar que los componentes sobrevivan intactos).
 */
export function parsearFechaLocal(valor: string): Date | null {
  const coincidencia = PATRON_FECHA_LOCAL.exec(valor);
  if (!coincidencia) return null;

  const anio = Number(coincidencia[1]);
  const mes = Number(coincidencia[2]);
  const dia = Number(coincidencia[3]);
  const fecha = new Date(Date.UTC(anio, mes - 1, dia));

  const esValida =
    fecha.getUTCFullYear() === anio &&
    fecha.getUTCMonth() === mes - 1 &&
    fecha.getUTCDate() === dia;
  return esValida ? fecha : null;
}

/** Serializa de vuelta a "YYYY-MM-DD" (inverso de parsearFechaLocal). */
export function formatearFechaLocal(fecha: Date): string {
  const anio = String(fecha.getUTCFullYear()).padStart(4, '0');
  const mes = String(fecha.getUTCMonth() + 1).padStart(2, '0');
  const dia = String(fecha.getUTCDate()).padStart(2, '0');
  return `${anio}-${mes}-${dia}`;
}

/**
 * Días completos entre dos fechas-calendario ya ancladas a medianoche UTC
 * (ver parsearFechaLocal). Positivo si `hasta` es posterior a `desde`.
 */
export function diferenciaEnDias(desde: Date, hasta: Date): number {
  return Math.round((hasta.getTime() - desde.getTime()) / MS_POR_DIA);
}

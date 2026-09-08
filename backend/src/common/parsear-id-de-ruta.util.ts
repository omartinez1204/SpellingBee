// Valida un :id de ruta como entero positivo dentro del rango seguro de
// Number (2^53-1). Sin el límite superior, un id absurdamente grande (p. ej.
// "999999999999999999999") pasa Number.isInteger() sin problema y luego
// truena en Prisma con un 500 genérico al no caber en el entero de 64 bits
// de SQLite — encontrado empíricamente al verificar T-023 y confirmado como
// el mismo defecto ya presente en T-021 (GET /niveles/:id/palabras).
export function parsearIdDeRuta(param: string): number | null {
  const id = Number(param);
  if (!Number.isInteger(id) || id <= 0 || id > Number.MAX_SAFE_INTEGER) {
    return null;
  }
  return id;
}

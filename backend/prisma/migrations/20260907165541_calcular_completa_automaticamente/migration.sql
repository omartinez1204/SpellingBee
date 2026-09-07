-- T-022: Palabra.completa pasa a ser un campo verdaderamente calculado,
-- mantenido por triggers de SQLite en vez de depender de que cada INSERT o
-- UPDATE se acuerde de fijarlo a mano (RF-08). Verdadero solo si los 3
-- campos de contenido están definidos y no son cadena vacía/solo espacios.
--
-- Se usan triggers y no una columna GENERATED para no romper schema.prisma:
-- Prisma sigue viendo "completa" como una columna normal @default(false),
-- escribible desde el cliente; el trigger simplemente la sobreescribe con el
-- valor correcto justo después de cada INSERT/UPDATE, sin importar qué haya
-- mandado (o no) quien escribió la fila. Es AFTER, no BEFORE, porque SQLite
-- no permite reasignar NEW.* dentro de un trigger; el patrón estándar es un
-- UPDATE de seguimiento sobre la fila recién escrita.
--
-- La cláusula WHEN evita una escritura de más cuando el valor ya es
-- correcto, y de paso hace inofensivo un eventual "PRAGMA recursive_triggers
-- = ON": la recursión se autodetiene en la segunda vuelta, porque ya no
-- quedaría nada por cambiar.

-- Normaliza las filas existentes. Defensivo: hoy las 45 palabras del
-- catálogo (T-003, bloqueado) ya están en completa=0 sin contenido, así que
-- esto no les cambia nada, pero deja la invariante garantizada para
-- cualquier fila que ya existiera antes de este trigger.
UPDATE "palabras"
SET "completa" = (
  "significado_es" IS NOT NULL AND TRIM("significado_es") != ''
  AND "oracion_ejemplo" IS NOT NULL AND TRIM("oracion_ejemplo") != ''
  AND "nombre_archivo_audio" IS NOT NULL AND TRIM("nombre_archivo_audio") != ''
);

CREATE TRIGGER "trg_palabras_completa_insert"
AFTER INSERT ON "palabras"
WHEN (
  (NEW."significado_es" IS NOT NULL AND TRIM(NEW."significado_es") != ''
   AND NEW."oracion_ejemplo" IS NOT NULL AND TRIM(NEW."oracion_ejemplo") != ''
   AND NEW."nombre_archivo_audio" IS NOT NULL AND TRIM(NEW."nombre_archivo_audio") != '')
  != NEW."completa"
)
BEGIN
  UPDATE "palabras"
  SET "completa" = (
    NEW."significado_es" IS NOT NULL AND TRIM(NEW."significado_es") != ''
    AND NEW."oracion_ejemplo" IS NOT NULL AND TRIM(NEW."oracion_ejemplo") != ''
    AND NEW."nombre_archivo_audio" IS NOT NULL AND TRIM(NEW."nombre_archivo_audio") != ''
  )
  WHERE "id" = NEW."id";
END;

CREATE TRIGGER "trg_palabras_completa_update"
AFTER UPDATE ON "palabras"
WHEN (
  (NEW."significado_es" IS NOT NULL AND TRIM(NEW."significado_es") != ''
   AND NEW."oracion_ejemplo" IS NOT NULL AND TRIM(NEW."oracion_ejemplo") != ''
   AND NEW."nombre_archivo_audio" IS NOT NULL AND TRIM(NEW."nombre_archivo_audio") != '')
  != NEW."completa"
)
BEGIN
  UPDATE "palabras"
  SET "completa" = (
    NEW."significado_es" IS NOT NULL AND TRIM(NEW."significado_es") != ''
    AND NEW."oracion_ejemplo" IS NOT NULL AND TRIM(NEW."oracion_ejemplo") != ''
    AND NEW."nombre_archivo_audio" IS NOT NULL AND TRIM(NEW."nombre_archivo_audio") != ''
  )
  WHERE "id" = NEW."id";
END;

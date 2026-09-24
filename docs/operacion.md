# Spelling Bee — Operación

Documento operativo (T-073), separado de `diseno-tecnico.md`: mientras ese documento traduce el ERS a decisiones de arquitectura y API, este cubre la operación del sistema. Por ahora contiene solo la política de respaldo de la base de datos (RNF-13).

## 1. Respaldo de la base de datos (RNF-13, T-073)

### 1.1 Política acordada con NovaUniversitas

- **Servidor**: el backend y la base de datos están en el mismo servidor.
- **Periodicidad**: semanal, cada fin de semana.
- **Quién**: el propio equipo de desarrollo ejecuta el respaldo y lo verifica.

Fuente: indicada por el equipo en la sesión de trabajo del 2026-09-22 (T-073). El ERS v1.14 todavía no la refleja.

### 1.2 Cómo correr el respaldo

```bash
cd backend
npm run respaldar-bd                      # destino por defecto: backend/backups/
npm run respaldar-bd -- <directorio>      # destino explícito
```

- Genera un único archivo `<nombre-de-la-bd>-AAAAMMDD-HHmmss.sqlite` (hora local). Puede correrse con el backend en marcha.
- Usa la Online Backup API de SQLite (`Database.prototype.backup()` de better-sqlite3, el mismo mecanismo que `sqlite3 <bd> ".backup <destino>"`), no una copia de archivo directa: la base corre en modo WAL y una copia directa pierde las escrituras que todavía viven solo en `<bd>.db-wal`. `backend/scripts/respaldar-bd.spec.ts` reproduce ese escenario.
- Antes de dejar el archivo con su nombre definitivo comprueba su integridad (`PRAGMA integrity_check`). Si algo falla, no queda ningún archivo en el destino y el script termina con código de salida distinto de cero y un mensaje en español.
- Respalda solo el archivo de base de datos SQLite; no incluye los audios (`backend/assets/audios/`), que viven fuera de la base.
- `backend/backups/` es únicamente el valor por defecto del script, no un destino definido por la política. Queda fuera de git: son copias de la base de datos real, no código.

### 1.3 Pendiente

- **Procedimiento de restauración: pendiente.** Todavía no existe un procedimiento de restauración definido y, por lo tanto, tampoco probado. No se resuelve en T-073; aquí solo se deja constancia. El script genera y verifica el respaldo; no lo restaura.
- **Automatización**: no se automatiza la programación (cron) mientras no haya un servidor de producción activo.

## Historial

- 2026-09-22 (T-073): primera versión.
- 2026-09-24 (revisión de T-073): §1.1 se limitó a lo indicado; el script pasó a generar un único archivo `.sqlite` y a no dejar ningún archivo si el respaldo falla (antes: extensión `.db`, dejaba `-wal`/`-shm` y, ante una base corrupta, un archivo corrupto con nombre de respaldo).

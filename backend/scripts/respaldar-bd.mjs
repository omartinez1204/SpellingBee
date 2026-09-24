#!/usr/bin/env node
// T-073 (RNF-13): respaldo del archivo de base de datos SQLite.
//
// Usa la Online Backup API de SQLite — Database.prototype.backup() de
// better-sqlite3, el mismo mecanismo que hay detrás de
// `sqlite3 <bd> ".backup <destino>"` en el CLI oficial — en vez de copiar el
// archivo .db con fs.copyFile. Motivo (RNF-13, ver también PrismaService):
// esta base de datos corre en modo WAL, así que una escritura reciente puede
// vivir SOLO en <bd>.db-wal, todavía no en <bd>.db; una copia cruda del .db a
// secas dejaría fuera exactamente esas filas. .backup() no tiene ese
// problema porque lee a través de una conexión SQLite real (que sí ve el
// contenido del WAL), no del archivo en disco directamente — verificado a
// propósito para esta tarea con un WAL sin checkpoint antes de escribir este
// script.
//
// Uso:
//   npm run respaldar-bd                       (desde backend/; destino por defecto: backend/backups/)
//   npm run respaldar-bd -- /ruta/al/destino    (destino explícito)
//   node scripts/respaldar-bd.mjs [directorio_destino]
//
// Genera UN solo archivo, <nombre-de-la-bd>-AAAAMMDD-HHmmss.sqlite. El
// directorio por defecto (backend/backups/) es solo un valor por defecto de
// este script, no un destino definido por ninguna política; queda fuera de
// git (ver .gitignore) porque son copias de la base de datos real, no
// código. Copiar los respaldos a otro lugar queda fuera del alcance de este
// script, y tampoco programa su propia ejecución periódica.
//
// La política de CUÁNDO correrlo y quién lo hace está en docs/operacion.md.

import { config as cargarEnv } from 'dotenv';
import Database from 'better-sqlite3';
import { existsSync, mkdirSync, renameSync, rmSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Raíz de backend/ (un nivel arriba de este archivo, que vive en
// backend/scripts/) — todas las rutas relativas de abajo se resuelven contra
// esto, nunca contra el directorio desde el que se invoque el script, para
// que `npm run respaldar-bd` y `node backend/scripts/respaldar-bd.mjs` desde
// otro cwd se comporten igual (verificado corriéndolo desde la raíz del repo
// y desde un directorio ajeno).
const raizBackend = fileURLToPath(new URL('..', import.meta.url));

cargarEnv({ path: path.join(raizBackend, '.env') });

function resolverRutaOrigen() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error(
      'No está definida DATABASE_URL (revisa backend/.env). No se puede saber qué archivo respaldar.',
    );
  }
  if (!url.startsWith('file:')) {
    throw new Error(
      `DATABASE_URL="${url}" no apunta a un archivo local (se esperaba "file:..."); este script solo respalda SQLite.`,
    );
  }
  const ruta = url.slice('file:'.length);
  // Mismo criterio que Prisma 7 (ver el comentario sobre esto en
  // backend/.gitignore): una ruta relativa en DATABASE_URL se resuelve
  // relativa a la raíz de backend/, no al cwd de quien invoca.
  return path.isAbsolute(ruta) ? ruta : path.resolve(raizBackend, ruta);
}

function formatearMarcaDeTiempo(fecha) {
  const con2Digitos = (n) => String(n).padStart(2, '0');
  const fechaParte = `${fecha.getFullYear()}${con2Digitos(fecha.getMonth() + 1)}${con2Digitos(fecha.getDate())}`;
  const horaParte = `${con2Digitos(fecha.getHours())}${con2Digitos(fecha.getMinutes())}${con2Digitos(fecha.getSeconds())}`;
  return `${fechaParte}-${horaParte}`;
}

async function main() {
  const rutaOrigen = resolverRutaOrigen();
  if (!existsSync(rutaOrigen)) {
    throw new Error(`No existe el archivo de base de datos: ${rutaOrigen}`);
  }

  const directorioDestino = path.resolve(
    process.argv[2] ?? path.join(raizBackend, 'backups'),
  );
  mkdirSync(directorioDestino, { recursive: true });

  const nombreBase = path.basename(rutaOrigen, path.extname(rutaOrigen));
  const rutaDestino = path.join(
    directorioDestino,
    `${nombreBase}-${formatearMarcaDeTiempo(new Date())}.sqlite`,
  );
  // El respaldo se escribe con este nombre provisional y solo pasa al
  // definitivo cuando ya superó la verificación de integridad: un respaldo
  // corrupto o a medias (falla a la mitad, proceso interrumpido) nunca queda
  // en la carpeta con aspecto de respaldo válido — con una ejecución
  // periódica, un archivo así pasaría por "el último respaldo".
  const rutaProvisional = `${rutaDestino}.parcial`;
  if (existsSync(rutaDestino) || existsSync(rutaProvisional)) {
    // Colisión de nombre (dos corridas en el mismo segundo): mejor fallar
    // claro que pisar un respaldo anterior en silencio.
    throw new Error(`Ya existe un respaldo con ese nombre: ${rutaDestino}`);
  }

  try {
    // Solo lectura: este proceso nunca debe poder escribir en la base de
    // datos real, pase lo que pase en el resto del script.
    const origen = new Database(rutaOrigen, { readonly: true, fileMustExist: true });
    try {
      await origen.backup(rutaProvisional);
    } finally {
      origen.close();
    }

    // Verificación mínima: que el archivo generado abra y SQLite lo reporte
    // íntegro, no solo que "se haya creado algo". Se abre con lectura y
    // escritura A PROPÓSITO (es la copia, nunca la base real): al cerrarse la
    // última conexión de una base en modo WAL, SQLite borra sus archivos
    // -wal y -shm; abierta en solo lectura los dejaría junto al respaldo.
    const copia = new Database(rutaProvisional, { fileMustExist: true });
    let integridad;
    try {
      integridad = copia.pragma('integrity_check', { simple: true });
    } finally {
      copia.close();
    }
    if (integridad !== 'ok') {
      throw new Error(
        `El respaldo se generó pero integrity_check no dijo "ok": ${integridad}`,
      );
    }

    renameSync(rutaProvisional, rutaDestino);
  } catch (error) {
    for (const sufijo of ['', '-wal', '-shm']) {
      rmSync(`${rutaProvisional}${sufijo}`, { force: true });
    }
    throw error;
  }

  const tamanoKB = (statSync(rutaDestino).size / 1024).toFixed(1);
  console.log(`Respaldo OK: ${rutaDestino} (${tamanoKB} KB, integridad verificada)`);
}

main().catch((error) => {
  console.error(`Respaldo FALLÓ: ${error.message}`);
  process.exitCode = 1;
});

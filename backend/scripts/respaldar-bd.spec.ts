// T-073 (RNF-13). Prueba de integración del script de respaldo: lo corre de
// verdad como subproceso (node scripts/respaldar-bd.mjs) contra una base de
// datos SQLite de prueba, nunca contra dev.db.
//
// La prueba central (primer test) es la razón de ser de T-073: reproduce a
// propósito el escenario de "inconsistencia por el modo WAL" que motivó no
// usar una copia de archivo directa — una fila que solo vive en el
// <bd>.db-wal (todavía sin checkpoint), con la conexión "escritora" TODAVÍA
// abierta (como el backend real, que nunca se detiene para respaldar) — y
// confirma que el respaldo generado sí la incluye.
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdtemp, rm, readdir } from 'node:fs/promises';
import { closeSync, existsSync, openSync, writeSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

// better-sqlite3 no publica tipos propios ni tiene @types — createRequire
// evita que TS busque una declaración que no existe (ver también
// src/prisma/prisma.service.ts, que llega a SQLite vía el adaptador de
// Prisma en vez de esta librería directamente).
const require = createRequire(import.meta.url);
// eslint-disable-next-line @typescript-eslint/no-var-requires
const Database = require('better-sqlite3');

const rutaScript = path.resolve(import.meta.dirname, 'respaldar-bd.mjs');

describe('scripts/respaldar-bd.mjs (T-073, RNF-13)', () => {
  let dirPrueba: string;
  let rutaOrigen: string;
  let dirDestino: string;

  beforeEach(async () => {
    dirPrueba = await mkdtemp(path.join(tmpdir(), 'respaldo-bd-prueba-'));
    rutaOrigen = path.join(dirPrueba, 'origen.db');
    dirDestino = path.join(dirPrueba, 'destino');
  });

  afterEach(async () => {
    await rm(dirPrueba, { recursive: true, force: true });
  });

  function correrScript(env: Record<string, string | undefined>) {
    return execFileSync('node', [rutaScript, dirDestino], {
      env: { ...process.env, ...env },
      encoding: 'utf8',
    });
  }

  async function unicoArchivoDeRespaldo(): Promise<string> {
    const nombres = (await readdir(dirDestino)).filter((n) => n.endsWith('.sqlite'));
    expect(nombres, 'debía crear exactamente un archivo .sqlite de respaldo').toHaveLength(1);
    return path.join(dirDestino, nombres[0]);
  }

  it(
    'incluye una fila que SOLO vive en el .db-wal (sin checkpoint), con la conexión "escritora" todavía abierta — la razón de no copiar el archivo a secas',
    async () => {
      const origen = new Database(rutaOrigen);
      origen.pragma('journal_mode = WAL');
      origen.exec('CREATE TABLE t (x TEXT)');
      origen.prepare('INSERT INTO t VALUES (?)').run('fila-en-el-archivo-principal');
      origen.pragma('wal_checkpoint(TRUNCATE)'); // esta SÍ queda en origen.db
      // Esta otra, a propósito, NO se checkpointea: queda solo en origen.db-wal.
      origen.prepare('INSERT INTO t VALUES (?)').run('fila-solo-en-el-wal');
      expect(existsSync(`${rutaOrigen}-wal`)).toBe(true);

      // La conexión "escritora" se queda abierta durante el respaldo — así
      // corre el backend real (nunca se detiene para poder respaldar).
      try {
        correrScript({ DATABASE_URL: `file:${rutaOrigen}` });

        const rutaRespaldo = await unicoArchivoDeRespaldo();
        const respaldo = new Database(rutaRespaldo, { readonly: true });
        try {
          const filas = respaldo.prepare('SELECT x FROM t ORDER BY x').all();
          expect(filas).toEqual([
            { x: 'fila-en-el-archivo-principal' },
            { x: 'fila-solo-en-el-wal' },
          ]);
          expect(respaldo.pragma('integrity_check', { simple: true })).toBe('ok');
        } finally {
          respaldo.close();
        }
      } finally {
        origen.close();
      }
    },
  );

  it('como CONTROL: una copia cruda del .db (sin el -wal) SÍ pierde esa fila — confirma que el riesgo que RNF-13 pide evitar es real, no solo teórico', async () => {
    const origen = new Database(rutaOrigen);
    origen.pragma('journal_mode = WAL');
    origen.exec('CREATE TABLE t (x TEXT)');
    origen.prepare('INSERT INTO t VALUES (?)').run('fila-en-el-archivo-principal');
    origen.pragma('wal_checkpoint(TRUNCATE)');
    origen.prepare('INSERT INTO t VALUES (?)').run('fila-solo-en-el-wal');

    const { copyFileSync } = await import('node:fs');
    const rutaCopiaCruda = path.join(dirPrueba, 'copia-cruda.db');
    copyFileSync(rutaOrigen, rutaCopiaCruda);
    origen.close();

    const copia = new Database(rutaCopiaCruda, { readonly: true });
    const filas = copia.prepare('SELECT x FROM t').all();
    copia.close();
    expect(filas).toEqual([{ x: 'fila-en-el-archivo-principal' }]); // falta la del WAL
  });

  it('genera un nombre de archivo .sqlite con marca de tiempo y reporta éxito en la salida', async () => {
    const origen = new Database(rutaOrigen);
    origen.pragma('journal_mode = WAL');
    origen.exec('CREATE TABLE t (x TEXT)');
    origen.close();

    const salida = correrScript({ DATABASE_URL: `file:${rutaOrigen}` });

    expect(salida).toMatch(/Respaldo OK: .*origen-\d{8}-\d{6}\.sqlite/);
    await unicoArchivoDeRespaldo();
  });

  it('deja UN solo archivo en el destino: ni -wal, ni -shm, ni el nombre provisional (.parcial)', async () => {
    // Origen en modo WAL a propósito: el respaldo hereda ese modo, y abrirlo
    // solo para leer (la verificación de integridad) dejaría junto a él sus
    // archivos -wal y -shm.
    const origen = new Database(rutaOrigen);
    origen.pragma('journal_mode = WAL');
    origen.exec('CREATE TABLE t (x TEXT)');
    origen.prepare('INSERT INTO t VALUES (?)').run('una-fila');
    try {
      correrScript({ DATABASE_URL: `file:${rutaOrigen}` });
    } finally {
      origen.close();
    }

    const contenido = await readdir(dirDestino);
    expect(contenido, 'el destino debía contener solo el respaldo').toHaveLength(1);
    expect(contenido[0]).toMatch(/^origen-\d{8}-\d{6}\.sqlite$/);
  });

  it('con el origen corrupto: falla, y NO deja ningún archivo en el destino (un respaldo corrupto nunca queda con aspecto de válido)', async () => {
    const origen = new Database(rutaOrigen);
    origen.pragma('journal_mode = WAL');
    origen.exec('CREATE TABLE t (x TEXT)');
    origen.prepare('INSERT INTO t VALUES (?)').run('una-fila');
    origen.pragma('wal_checkpoint(TRUNCATE)');
    const tamanoPagina = origen.pragma('page_size', { simple: true }) as number;
    const paginaRaiz = origen.prepare("SELECT rootpage FROM sqlite_master WHERE name = 't'").get()
      .rootpage as number;
    origen.close();

    // Corrompe el tipo de la página raíz de la tabla (0 no es un tipo de
    // página B-tree válido): la cabecera del archivo queda intacta, así que
    // SQLite lo abre y .backup() copia las páginas tal cual; solo
    // integrity_check ve el daño — la situación que hay que cubrir.
    const descriptor = openSync(rutaOrigen, 'r+');
    writeSync(descriptor, Buffer.from([0x00]), 0, 1, (paginaRaiz - 1) * tamanoPagina);
    closeSync(descriptor);

    expect(() => correrScript({ DATABASE_URL: `file:${rutaOrigen}` })).toThrow(
      /integrity_check no dijo "ok"/,
    );
    expect(await readdir(dirDestino), 'el destino debía quedar vacío').toEqual([]);
  });

  it('sin DATABASE_URL: falla claro (en español) y no crea ningún archivo', async () => {
    // '' y no undefined a propósito: undefined hace que Node quite la
    // variable del entorno del hijo, y entonces sí quedaría "sin definir" —
    // pero el propio script vuelve a cargar backend/.env con dotenv, que
    // rellenaría la real DATABASE_URL="file:./dev.db" (dotenv solo respeta
    // una variable que YA existe, aunque esté vacía; no una ausente). Una
    // cadena vacía sigue siendo "falsy" para el script (mismo camino que
    // "no está definida") pero SÍ existe, así que dotenv no la toca.
    expect(() => correrScript({ DATABASE_URL: '' })).toThrow(
      /No está definida DATABASE_URL/,
    );
    expect(existsSync(dirDestino)).toBe(false);
  });

  it('DATABASE_URL apunta a un archivo que no existe: falla claro y no crea nada', () => {
    const rutaInexistente = path.join(dirPrueba, 'no-existe.db');
    expect(() => correrScript({ DATABASE_URL: `file:${rutaInexistente}` })).toThrow(
      /No existe el archivo de base de datos/,
    );
    expect(existsSync(dirDestino)).toBe(false);
  });

  it('DATABASE_URL no es un archivo local (p. ej. un motor cliente-servidor): falla claro en vez de intentar algo raro', () => {
    expect(() =>
      correrScript({ DATABASE_URL: 'postgresql://usuario:clave@host/bd' }),
    ).toThrow(/no apunta a un archivo local/);
  });
});

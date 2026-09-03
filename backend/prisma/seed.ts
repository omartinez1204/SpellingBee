// Seed de datos iniciales: T-002 (niveles + cuentas de profesor) y T-003
// (catálogo de 45 palabras, solo texto + nivel). NO incluye T-002b/futuro:
// significado, oración de ejemplo y audio de cada palabra siguen bloqueados
// (ver docs/backlog.md, "Bloqueadores" — T-003).
import 'dotenv/config';
import { randomInt } from 'node:crypto';
import bcrypt from 'bcrypt';
import { PrismaBetterSqlite3 } from '@prisma/adapter-better-sqlite3';
import { PrismaClient } from '../src/generated/prisma/client.js';

const BCRYPT_COST = 12;
const TEMP_PASSWORD_LENGTH = 14;
// Sin 0/O/1/l/I: un profesor puede tener que transcribirla a mano en el primer login.
const TEMP_PASSWORD_ALPHABET =
  'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

function generarContrasenaTemporal(): string {
  let password = '';
  for (let i = 0; i < TEMP_PASSWORD_LENGTH; i++) {
    password +=
      TEMP_PASSWORD_ALPHABET[randomInt(TEMP_PASSWORD_ALPHABET.length)];
  }
  return password;
}

const adapter = new PrismaBetterSqlite3({
  url: process.env.DATABASE_URL ?? 'file:./dev.db',
});
const prisma = new PrismaClient({ adapter });

async function seedNiveles() {
  const count = await prisma.nivel.count();
  if (count > 0) {
    console.log(
      `niveles: ya hay ${count} en la base, no se insertan de nuevo.`,
    );
    return;
  }

  await prisma.nivel.createMany({
    data: [
      { nombre: 'Fácil', orden: 1 },
      { nombre: 'Intermedio', orden: 2 },
      { nombre: 'Difícil', orden: 3 },
    ],
  });
  console.log('niveles: Fácil, Intermedio y Difícil creados (RF-05).');
}

// RF-02/RF-36. Los correos son un placeholder (@example.com): NovaUniversitas
// todavía no ha proporcionado las direcciones reales de estas 2 cuentas —
// hay que sustituirlas cuando se tengan (ver docs/backlog.md, "Bloqueadores").
const CUENTAS_PROFESOR = ['profesorIngles', 'profesorInglesb'] as const;

async function seedCuentaProfesor(nombreUsuario: string) {
  const existente = await prisma.usuario.findUnique({
    where: { nombreUsuario },
  });
  if (existente) {
    console.log(
      `profesor "${nombreUsuario}": ya existe, no se toca su contraseña.`,
    );
    return;
  }

  const passwordTemporal = generarContrasenaTemporal();
  const contrasenaHash = await bcrypt.hash(passwordTemporal, BCRYPT_COST);
  const correoPlaceholder = `${nombreUsuario.toLowerCase()}@example.com`;

  await prisma.usuario.create({
    data: {
      nombreUsuario,
      contrasenaHash,
      rol: 'profesor',
      correoElectronico: correoPlaceholder,
      correoRecuperacion: correoPlaceholder,
      debeCambiarContrasena: true,
    },
  });

  console.log('');
  console.log(`profesor "${nombreUsuario}" creado:`);
  console.log(
    `  contraseña temporal (solo se muestra esta vez): ${passwordTemporal}`,
  );
  console.log(
    `  correo (placeholder, pendiente del dato real):  ${correoPlaceholder}`,
  );
}

// T-003. Anexo B del ERS, transcrito de docs/catalogo-palabras.ods (Hoja1).
// "requirement" aparece dos veces en Difícil a propósito (ver docs/backlog.md,
// "Bloqueadores": son dos registros independientes con su propio id, no se
// deduplican aquí). Significado, oración de ejemplo y audio quedan pendientes
// (bloqueado) — no se inventan placeholders para esos 3 campos.
type NombreNivel = 'Fácil' | 'Intermedio' | 'Difícil';

const CATALOGO_PALABRAS: { texto: string; nivel: NombreNivel }[] = [
  // Fácil (15)
  { texto: 'business', nivel: 'Fácil' },
  { texto: 'payment', nivel: 'Fácil' },
  { texto: 'distance', nivel: 'Fácil' },
  { texto: 'opposite', nivel: 'Fácil' },
  { texto: 'collect', nivel: 'Fácil' },
  { texto: 'laundry', nivel: 'Fácil' },
  { texto: 'mistake', nivel: 'Fácil' },
  { texto: 'world', nivel: 'Fácil' },
  { texto: 'boring', nivel: 'Fácil' },
  { texto: 'solution', nivel: 'Fácil' },
  { texto: 'memory', nivel: 'Fácil' },
  { texto: 'choice', nivel: 'Fácil' },
  { texto: 'holiday', nivel: 'Fácil' },
  { texto: 'survey', nivel: 'Fácil' },
  { texto: 'again', nivel: 'Fácil' },
  // Intermedio (15)
  { texto: 'together', nivel: 'Intermedio' },
  { texto: 'childhood', nivel: 'Intermedio' },
  { texto: 'microwave', nivel: 'Intermedio' },
  { texto: 'absolutely', nivel: 'Intermedio' },
  { texto: 'adventure', nivel: 'Intermedio' },
  { texto: 'luggage', nivel: 'Intermedio' },
  { texto: 'experiment', nivel: 'Intermedio' },
  { texto: 'download', nivel: 'Intermedio' },
  { texto: 'headache', nivel: 'Intermedio' },
  { texto: 'measure', nivel: 'Intermedio' },
  { texto: 'departure', nivel: 'Intermedio' },
  { texto: 'enough', nivel: 'Intermedio' },
  { texto: 'language', nivel: 'Intermedio' },
  { texto: 'delivery', nivel: 'Intermedio' },
  { texto: 'necessary', nivel: 'Intermedio' },
  // Difícil (15, incluye "requirement" dos veces — ver comentario arriba)
  { texto: 'requirement', nivel: 'Difícil' },
  { texto: 'neighbor', nivel: 'Difícil' },
  { texto: 'unfortunately', nivel: 'Difícil' },
  { texto: 'communication', nivel: 'Difícil' },
  { texto: 'pronunciation', nivel: 'Difícil' },
  { texto: 'punctuation', nivel: 'Difícil' },
  { texto: 'apologize', nivel: 'Difícil' },
  { texto: 'requirement', nivel: 'Difícil' },
  { texto: 'appointment', nivel: 'Difícil' },
  { texto: 'marshmallow', nivel: 'Difícil' },
  { texto: 'inappropriate', nivel: 'Difícil' },
  { texto: 'environmental', nivel: 'Difícil' },
  { texto: 'unforgettable', nivel: 'Difícil' },
  { texto: 'fashionable', nivel: 'Difícil' },
  { texto: 'responsibility', nivel: 'Difícil' },
];

async function seedCatalogoPalabras() {
  const count = await prisma.palabra.count();
  if (count > 0) {
    console.log(
      `catálogo: ya hay ${count} palabras en la base, no se insertan de nuevo.`,
    );
    return;
  }

  const niveles = await prisma.nivel.findMany();
  const idNivelPorNombre = new Map(niveles.map((n) => [n.nombre, n.id]));

  const autor = await prisma.usuario.findUnique({
    where: { nombreUsuario: 'profesorIngles' },
  });
  if (!autor) {
    throw new Error(
      'seedCatalogoPalabras: no existe "profesorIngles" — corre seedCuentaProfesor antes.',
    );
  }

  const data = CATALOGO_PALABRAS.map(({ texto, nivel }) => {
    const idNivel = idNivelPorNombre.get(nivel);
    if (idNivel === undefined) {
      throw new Error(`seedCatalogoPalabras: no existe el nivel "${nivel}".`);
    }
    // significadoEs, oracionEjemplo y nombreArchivoAudio se omiten a propósito:
    // deben quedar NULL (T-003, bloqueado), no un placeholder inventado.
    return { texto, idNivel, idProfesorAutor: autor.id };
  });

  await prisma.palabra.createMany({ data });
  console.log(
    `catálogo: ${data.length} palabras cargadas (15 por nivel, T-003). ` +
      'significado, oración y audio quedan pendientes (bloqueado).',
  );
}

async function main() {
  await prisma.$connect();
  // ERS §7 / docs/diseno-tecnico.md §1: SQLite en modo WAL. Se reafirma aquí
  // por si el seed corre antes que la app haya abierto una conexión al .db.
  await prisma.$executeRawUnsafe('PRAGMA journal_mode = WAL;');

  await seedNiveles();
  for (const nombreUsuario of CUENTAS_PROFESOR) {
    await seedCuentaProfesor(nombreUsuario);
  }
  await seedCatalogoPalabras();
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });

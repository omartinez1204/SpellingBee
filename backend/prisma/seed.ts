// T-002: seed de datos iniciales. NO incluye T-003 (catálogo de palabras).
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

async function main() {
  await prisma.$connect();
  // ERS §7 / docs/diseno-tecnico.md §1: SQLite en modo WAL. Se reafirma aquí
  // por si el seed corre antes que la app haya abierto una conexión al .db.
  await prisma.$executeRawUnsafe('PRAGMA journal_mode = WAL;');

  await seedNiveles();
  for (const nombreUsuario of CUENTAS_PROFESOR) {
    await seedCuentaProfesor(nombreUsuario);
  }
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

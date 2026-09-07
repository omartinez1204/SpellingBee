import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const PREFIJO_PRUEBA = 'TEST-T022-';

// T-022: Palabra.completa se recalcula automáticamente (triggers de SQLite,
// ver prisma/migrations/20260907165541_calcular_completa_automaticamente).
// No hay endpoint todavía que cree/edite palabras (eso es T-024) — estas
// pruebas hablan con Prisma directamente, que es exactamente la capa que el
// trigger debe gobernar sin que nadie tenga que acordarse de nada.
describe('Palabra.completa - recálculo automático (T-022)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let idNivel: number;
  let idProfesorAutor: number;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    const nivel = await prisma.nivel.findFirst({ where: { nombre: 'Fácil' } });
    const profesor = await prisma.usuario.findUnique({
      where: { nombreUsuario: 'profesorIngles' },
    });
    if (!nivel || !profesor) {
      throw new Error(
        'Faltan datos de seed (nivel "Fácil" o "profesorIngles") — corre el seed antes de las pruebas.',
      );
    }
    idNivel = nivel.id;
    idProfesorAutor = profesor.id;
  });

  afterEach(async () => {
    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await app.close();
  });

  // El valor que Prisma regresa en el propio create()/update() puede no
  // reflejar el trigger todavía: RETURNING no ve el UPDATE de seguimiento
  // que el propio trigger hace sobre esa misma fila (confirmado
  // empíricamente al implementar T-022). Por eso cada aserción vuelve a leer
  // la fila en vez de confiar en el valor de retorno de la mutación.
  async function completaDe(id: number): Promise<boolean> {
    const fila = await prisma.palabra.findUniqueOrThrow({
      where: { id },
      select: { completa: true },
    });
    return fila.completa;
  }

  it('una palabra creada solo con texto y nivel queda completa=false', async () => {
    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}nueva`, idNivel, idProfesorAutor },
    });

    expect(await completaDe(palabra.id)).toBe(false);
  });

  it('al llenar los 3 campos de contenido en una sola edición, pasa a completa=true automáticamente', async () => {
    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}se-completa`, idNivel, idProfesorAutor },
    });
    expect(await completaDe(palabra.id)).toBe(false);

    await prisma.palabra.update({
      where: { id: palabra.id },
      data: {
        significadoEs: 'significado de prueba',
        oracionEjemplo: 'This is a test sentence.',
        nombreArchivoAudio: `${palabra.id}.mp3`,
      },
    });

    expect(await completaDe(palabra.id)).toBe(true);
  });

  it('creada de una sola vez con los 3 campos ya llenos, queda completa=true desde el create', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}completa-desde-el-create`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado de prueba',
        oracionEjemplo: 'This is a test sentence.',
        nombreArchivoAudio: '1.mp3',
      },
    });

    expect(await completaDe(palabra.id)).toBe(true);
  });

  it('también se completa si los 3 campos se llenan en ediciones separadas, una por una', async () => {
    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}se-completa-por-partes`, idNivel, idProfesorAutor },
    });
    expect(await completaDe(palabra.id)).toBe(false);

    // Cada campo en su propia llamada a update(), simulando ediciones
    // separadas en el tiempo (p. ej. capturar significado hoy, oración
    // mañana, audio la próxima semana) — no un solo payload con los 3.
    await prisma.palabra.update({
      where: { id: palabra.id },
      data: { significadoEs: 'significado de prueba' },
    });
    expect(await completaDe(palabra.id)).toBe(false);

    await prisma.palabra.update({
      where: { id: palabra.id },
      data: { oracionEjemplo: 'This is a test sentence.' },
    });
    expect(await completaDe(palabra.id)).toBe(false);

    await prisma.palabra.update({
      where: { id: palabra.id },
      data: { nombreArchivoAudio: `${palabra.id}.mp3` },
    });
    expect(await completaDe(palabra.id)).toBe(true);
  });

  it('con solo 2 de los 3 campos llenos, sigue en completa=false', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}parcial`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado',
        oracionEjemplo: 'An example sentence.',
      },
    });

    expect(await completaDe(palabra.id)).toBe(false);
  });

  it('un campo con solo espacios en blanco no cuenta como lleno', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}espacios`,
        idNivel,
        idProfesorAutor,
        significadoEs: '   ',
        oracionEjemplo: 'An example sentence.',
        nombreArchivoAudio: '1.mp3',
      },
    });

    expect(await completaDe(palabra.id)).toBe(false);
  });

  it('si después se vacía (cadena vacía) uno de los 3 campos, vuelve a completa=false', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}se-descompleta`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado',
        oracionEjemplo: 'An example sentence.',
        nombreArchivoAudio: '1.mp3',
      },
    });
    expect(await completaDe(palabra.id)).toBe(true);

    await prisma.palabra.update({
      where: { id: palabra.id },
      data: { oracionEjemplo: '' },
    });

    expect(await completaDe(palabra.id)).toBe(false);
  });

  it('si después se borra (null, no solo cadena vacía) uno de los 3 campos, vuelve a completa=false', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}se-descompleta-null`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado',
        oracionEjemplo: 'An example sentence.',
        nombreArchivoAudio: '1.mp3',
      },
    });
    expect(await completaDe(palabra.id)).toBe(true);

    await prisma.palabra.update({
      where: { id: palabra.id },
      data: { significadoEs: null },
    });

    expect(await completaDe(palabra.id)).toBe(false);
  });

  it('no afecta palabras de otras filas (recalcula solo la fila escrita)', async () => {
    const testigo = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}testigo`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado',
        oracionEjemplo: 'An example sentence.',
        nombreArchivoAudio: '1.mp3',
      },
    });
    expect(await completaDe(testigo.id)).toBe(true);

    const otra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}otra`, idNivel, idProfesorAutor },
    });

    expect(await completaDe(otra.id)).toBe(false);
    expect(await completaDe(testigo.id)).toBe(true);
  });
});

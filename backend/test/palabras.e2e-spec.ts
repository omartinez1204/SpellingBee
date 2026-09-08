import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const PREFIJO_PRUEBA = 'TEST-T023-';

describe('PalabrasController (e2e) - GET /palabras/:id', () => {
  let app: INestApplication<App>;
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

  // RF-07: "el sistema debe mostrar... la palabra... y un ícono para
  // reproducir su audio... el significado... y la oración de ejemplo...
  // deben permanecer ocultos al inicio, disponibles mediante dos botones de
  // pista". diseno-tecnico.md aclara que el backend siempre regresa los 4
  // campos — el ocultamiento es responsabilidad del cliente, no de aquí.
  it('regresa los 4 campos aunque significado/oración/audio todavía no existan', async () => {
    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}incompleta`, idNivel, idProfesorAutor },
    });

    const respuesta = await request(app.getHttpServer())
      .get(`/palabras/${palabra.id}`)
      .expect(200);

    expect(respuesta.body).toEqual({
      id: palabra.id,
      texto: `${PREFIJO_PRUEBA}incompleta`,
      significado_es: null,
      oracion_ejemplo: null,
      url_audio: null,
    });
  });

  it('regresa los 4 campos con contenido real, incluida una url de audio construida a partir del archivo', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}completa`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado de prueba',
        oracionEjemplo: 'This is a test sentence.',
        nombreArchivoAudio: '999.mp3',
      },
    });

    const respuesta = await request(app.getHttpServer())
      .get(`/palabras/${palabra.id}`)
      .expect(200);

    expect(respuesta.body).toEqual({
      id: palabra.id,
      texto: `${PREFIJO_PRUEBA}completa`,
      significado_es: 'significado de prueba',
      oracion_ejemplo: 'This is a test sentence.',
      url_audio: '/assets/audios/999.mp3',
    });
  });

  // Decisión deliberada (ver comentario en palabras.service.ts): a
  // diferencia de GET /niveles/:id/palabras (T-021), este endpoint de
  // detalle NO filtra por oculta — ni el ERS ni diseno-tecnico.md lo piden
  // aquí, solo en el listado. Esta prueba deja esa decisión visible y
  // verificable, no escondida.
  it('también regresa el detalle de una palabra oculta (no filtra por oculta, a propósito)', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}oculta`,
        idNivel,
        idProfesorAutor,
        oculta: true,
        significadoEs: 'significado',
        oracionEjemplo: 'An example sentence.',
        nombreArchivoAudio: '1.mp3',
      },
    });

    await request(app.getHttpServer())
      .get(`/palabras/${palabra.id}`)
      .expect(200);
  });

  it('regresa el detalle de una palabra incompleta Y oculta a la vez, sin filtrar ninguna de las dos', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}incompleta-oculta`,
        idNivel,
        idProfesorAutor,
        oculta: true,
        // sin significado/oración/audio: completa=false por el trigger de T-022.
      },
    });

    const respuesta = await request(app.getHttpServer())
      .get(`/palabras/${palabra.id}`)
      .expect(200);

    expect(respuesta.body).toEqual({
      id: palabra.id,
      texto: `${PREFIJO_PRUEBA}incompleta-oculta`,
      significado_es: null,
      oracion_ejemplo: null,
      url_audio: null,
    });
  });

  it('un nombre_archivo_audio en cadena vacía (no null) también da url_audio=null, sin construir una url rota', async () => {
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}audio-vacio`,
        idNivel,
        idProfesorAutor,
        nombreArchivoAudio: '',
      },
    });

    const respuesta = await request(app.getHttpServer())
      .get(`/palabras/${palabra.id}`)
      .expect(200);

    expect(respuesta.body.url_audio).toBeNull();
  });

  it('404 con mensaje en español si la palabra no existe', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/palabras/999999')
      .expect(404);

    expect(respuesta.body).toEqual({
      error: {
        code: 'PALABRA_NO_ENCONTRADA',
        message: 'No existe una palabra con ese id.',
      },
    });
  });

  it('400 con mensaje en español si el id no es numérico', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/palabras/abc')
      .expect(400);

    expect(respuesta.body).toEqual({
      error: {
        code: 'PALABRA_ID_INVALIDO',
        message: 'El id de palabra debe ser un número entero positivo.',
      },
    });
  });

  it('400 (no 500) si el id es negativo', async () => {
    await request(app.getHttpServer()).get('/palabras/-1').expect(400);
  });

  it('400 (no 500) si el id es decimal', async () => {
    await request(app.getHttpServer()).get('/palabras/1.5').expect(400);
  });

  // Bug real encontrado al verificar T-023: Number.isInteger(1e21) es true
  // (los flotantes grandes sin fracción "son" enteros para JS), así que un
  // id absurdamente grande pasaba la validación y luego tronaba en Prisma
  // con un 500 genérico al no caber en el entero de 64 bits de SQLite.
  it('400 (no 500) si el id es un número demasiado grande para un entero de 64 bits', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/palabras/999999999999999999999')
      .expect(400);

    expect(respuesta.body).toEqual({
      error: {
        code: 'PALABRA_ID_INVALIDO',
        message: 'El id de palabra debe ser un número entero positivo.',
      },
    });
  });

  it('400 (no 500) si el id es cero', async () => {
    await request(app.getHttpServer()).get('/palabras/0').expect(400);
  });

  it('no requiere sesión iniciada', async () => {
    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}publica`, idNivel, idProfesorAutor },
    });

    await request(app.getHttpServer())
      .get(`/palabras/${palabra.id}`)
      .expect(200);
  });
});

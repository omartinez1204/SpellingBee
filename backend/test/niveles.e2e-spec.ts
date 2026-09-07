import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const PREFIJO_PRUEBA = 'TEST-T021-';

describe('NivelesController (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
  });

  afterEach(async () => {
    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await app.close();
  });

  describe('GET /niveles', () => {
    // RF-05: "El sistema debe mostrar los tres niveles disponibles: Nivel 1
    // (Fácil), Nivel 2 (Intermedio) y Nivel 3 (Difícil)".
    it('regresa los 3 niveles del seed, en orden Fácil/Intermedio/Difícil', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/niveles')
        .expect(200);

      expect(respuesta.body).toHaveLength(3);
      expect(respuesta.body).toEqual([
        { id: expect.any(Number), nombre: 'Fácil', orden: 1 },
        { id: expect.any(Number), nombre: 'Intermedio', orden: 2 },
        { id: expect.any(Number), nombre: 'Difícil', orden: 3 },
      ]);
    });

    it('no requiere sesión iniciada', async () => {
      // Sin encabezado Authorization: diseno-tecnico.md §3.2 no marca esta
      // ruta como protegida, a diferencia de las de admin (§3.3/§3.5).
      await request(app.getHttpServer()).get('/niveles').expect(200);
    });
  });

  describe('GET /niveles/:id/palabras', () => {
    async function nivelPorNombre(nombre: string) {
      const nivel = await prisma.nivel.findFirst({ where: { nombre } });
      if (!nivel) throw new Error(`No existe el nivel "${nombre}" en el seed.`);
      return nivel;
    }

    async function idProfesorAutor() {
      const profesor = await prisma.usuario.findUnique({
        where: { nombreUsuario: 'profesorIngles' },
      });
      if (!profesor) {
        throw new Error(
          'No existe "profesorIngles" — corre el seed antes de las pruebas.',
        );
      }
      return profesor.id;
    }

    // Estado real del catálogo hoy: T-022 (recálculo automático de
    // `completa`) todavía no existe, y las 45 palabras del Anexo B se
    // insertaron sin significado/oración/audio (T-003, bloqueado) — así que
    // ninguna puede tener completa=true todavía. Una lista vacía aquí es el
    // resultado correcto, no un síntoma de que el endpoint esté roto.
    it('con el catálogo real (sin recálculo de completa todavía) regresa una lista vacía', async () => {
      const facil = await nivelPorNombre('Fácil');

      const respuesta = await request(app.getHttpServer())
        .get(`/niveles/${facil.id}/palabras`)
        .expect(200);

      expect(respuesta.body).toEqual([]);
    });

    it('incluye solo palabras completa=true AND oculta=false del nivel pedido', async () => {
      const facil = await nivelPorNombre('Fácil');
      const intermedio = await nivelPorNombre('Intermedio');
      const idProfesor = await idProfesorAutor();

      // completa ya no se puede fijar a mano (T-022: un trigger la
      // recalcula en cada create/update a partir de estos 3 campos) — para
      // que una palabra de prueba quede completa=true hay que darle
      // contenido real, no solo poner `completa: true` en el fixture.
      const contenidoCompleto = {
        significadoEs: 'significado de prueba',
        oracionEjemplo: 'An example sentence.',
        nombreArchivoAudio: 'x.mp3',
      };

      const visible = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}completa-visible`,
          idNivel: facil.id,
          oculta: false,
          idProfesorAutor: idProfesor,
          ...contenidoCompleto,
        },
      });
      await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}completa-oculta`,
          idNivel: facil.id,
          oculta: true,
          idProfesorAutor: idProfesor,
          ...contenidoCompleto,
        },
      });
      await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}incompleta-visible`,
          idNivel: facil.id,
          oculta: false,
          idProfesorAutor: idProfesor,
          // sin contenido: debe quedar completa=false por el trigger.
        },
      });
      await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}completa-visible-otro-nivel`,
          idNivel: intermedio.id,
          oculta: false,
          idProfesorAutor: idProfesor,
          ...contenidoCompleto,
        },
      });

      const respuesta = await request(app.getHttpServer())
        .get(`/niveles/${facil.id}/palabras`)
        .expect(200);

      expect(respuesta.body).toEqual([
        { id: visible.id, texto: visible.texto },
      ]);
    });

    it('404 con mensaje en español si el nivel no existe', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/niveles/999999/palabras')
        .expect(404);

      expect(respuesta.body).toEqual({
        error: {
          code: 'NIVEL_NO_ENCONTRADO',
          message: 'No existe un nivel con ese id.',
        },
      });
    });

    it('400 con mensaje en español si el id no es numérico', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/niveles/abc/palabras')
        .expect(400);

      expect(respuesta.body).toEqual({
        error: {
          code: 'NIVEL_ID_INVALIDO',
          message: 'El id de nivel debe ser un número entero positivo.',
        },
      });
    });

    it('no requiere sesión iniciada', async () => {
      const facil = await nivelPorNombre('Fácil');
      await request(app.getHttpServer())
        .get(`/niveles/${facil.id}/palabras`)
        .expect(200);
    });
  });
});

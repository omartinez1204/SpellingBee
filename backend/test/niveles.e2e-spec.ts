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

      // Desde T-070 (RNF-12) la lista viene paginada: { palabras, total, ... }.
      expect(respuesta.body).toEqual({
        palabras: [],
        total: 0,
        pagina: 1,
        limite: 20,
        total_paginas: 1,
      });
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

      expect(respuesta.body).toEqual({
        palabras: [{ id: visible.id, texto: visible.texto }],
        total: 1,
        pagina: 1,
        limite: 20,
        total_paginas: 1,
      });
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

    // Mismo bug encontrado y corregido al verificar T-023 (ver
    // src/common/parsear-id-de-ruta.util.ts): Number.isInteger(1e21) es
    // true, así que sin el límite superior este id absurdamente grande
    // pasaba la validación y tronaba en Prisma con un 500 genérico.
    it('400 (no 500) si el id es un número demasiado grande para un entero de 64 bits', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/niveles/999999999999999999999/palabras')
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

    // RNF-12 (T-070): un nivel puede acumular más de 50 palabras listas para
    // practicar. Se siembran 55 (por encima del umbral) más ruido que NO debe
    // contar (ocultas, incompletas, de otro nivel) y se comprueba que la
    // respuesta nunca trae el conjunto completo de una vez y que recorrer las
    // páginas entrega cada palabra exactamente una vez.
    describe('paginación (RNF-12, T-070)', () => {
      const SEMBRADAS = 55;

      async function sembrar() {
        const facil = await nivelPorNombre('Fácil');
        const intermedio = await nivelPorNombre('Intermedio');
        const idProfesor = await idProfesorAutor();
        const contenidoCompleto = {
          significadoEs: 'significado de prueba',
          oracionEjemplo: 'An example sentence.',
          nombreArchivoAudio: 'x.mp3',
        };

        // Por si el catálogo real ya tuviera palabras listas en este nivel.
        const previas = await prisma.palabra.count({
          where: { idNivel: facil.id, completa: true, oculta: false },
        });

        await prisma.palabra.createMany({
          data: Array.from({ length: SEMBRADAS }, (_, i) => ({
            texto: `${PREFIJO_PRUEBA}pag-${String(i).padStart(3, '0')}`,
            idNivel: facil.id,
            idProfesorAutor: idProfesor,
            ...contenidoCompleto,
          })),
        });
        // Ruido: ninguna de estas debe aparecer ni sumar al total.
        await prisma.palabra.createMany({
          data: [
            ...[0, 1, 2].map((i) => ({
              texto: `${PREFIJO_PRUEBA}ruido-oculta-${i}`,
              idNivel: facil.id,
              idProfesorAutor: idProfesor,
              oculta: true,
              ...contenidoCompleto,
            })),
            ...[0, 1, 2].map((i) => ({
              texto: `${PREFIJO_PRUEBA}ruido-incompleta-${i}`,
              idNivel: facil.id,
              idProfesorAutor: idProfesor,
            })),
            ...[0, 1, 2].map((i) => ({
              texto: `${PREFIJO_PRUEBA}ruido-otro-nivel-${i}`,
              idNivel: intermedio.id,
              idProfesorAutor: idProfesor,
              ...contenidoCompleto,
            })),
          ],
        });

        const idsSembrados = (
          await prisma.palabra.findMany({
            where: { texto: { startsWith: `${PREFIJO_PRUEBA}pag-` } },
            orderBy: { id: 'asc' },
            select: { id: true },
          })
        ).map((p) => p.id);

        return { facil, idsSembrados, total: previas + SEMBRADAS };
      }

      type Pagina = {
        palabras: { id: number; texto: string }[];
        total: number;
        pagina: number;
        limite: number;
        total_paginas: number;
      };

      async function pedirPagina(
        idNivel: number,
        query: Record<string, string | number>,
      ) {
        const respuesta = await request(app.getHttpServer())
          .get(`/niveles/${idNivel}/palabras`)
          .query(query)
          .expect(200);
        return respuesta.body as Pagina;
      }

      it('sin parámetros trae solo la primera página (20), no las 55 de una vez, con sus metadatos', async () => {
        const { facil, total } = await sembrar();

        const cuerpo = await pedirPagina(facil.id, {});

        expect(cuerpo.palabras).toHaveLength(20);
        expect(cuerpo.total).toBe(total);
        expect(cuerpo.pagina).toBe(1);
        expect(cuerpo.limite).toBe(20);
        expect(cuerpo.total_paginas).toBe(Math.ceil(total / 20));
      });

      it('recorrer todas las páginas entrega cada palabra exactamente una vez y en orden ascendente por id', async () => {
        const { facil, idsSembrados, total } = await sembrar();

        const vistos: number[] = [];
        const primera = await pedirPagina(facil.id, { pagina: 1, limite: 20 });
        for (let pagina = 1; pagina <= primera.total_paginas; pagina++) {
          const cuerpo = await pedirPagina(facil.id, { pagina, limite: 20 });
          // Ninguna página supera el límite pedido.
          expect(cuerpo.palabras.length).toBeLessThanOrEqual(20);
          vistos.push(...cuerpo.palabras.map((p) => p.id));
        }

        expect(vistos).toHaveLength(total);
        expect(new Set(vistos).size).toBe(total); // sin repetidas
        expect(vistos).toEqual([...vistos].sort((a, b) => a - b));
        expect(vistos).toEqual(expect.arrayContaining(idsSembrados)); // sin omitidas
      });

      it('el ruido (ocultas, incompletas, de otro nivel) no cuenta en total ni aparece', async () => {
        const { facil, total } = await sembrar();

        const cuerpo = await pedirPagina(facil.id, { limite: 50 });

        expect(cuerpo.total).toBe(total);
        const textos = cuerpo.palabras.map((p) => p.texto);
        expect(textos.some((t) => t.includes('ruido'))).toBe(false);
      });

      it('limite=50 (el tope) devuelve como máximo 50 por página y el resto en la siguiente', async () => {
        const { facil, total } = await sembrar();

        const pagina1 = await pedirPagina(facil.id, { pagina: 1, limite: 50 });
        const pagina2 = await pedirPagina(facil.id, { pagina: 2, limite: 50 });

        expect(pagina1.palabras).toHaveLength(50);
        expect(pagina1.total_paginas).toBe(Math.ceil(total / 50));
        expect(pagina2.palabras).toHaveLength(total - 50);
      });

      it('una página más allá del final regresa 200 con lista vacía (no un error) y el mismo total', async () => {
        const { facil, total } = await sembrar();

        const cuerpo = await pedirPagina(facil.id, { pagina: 99 });

        expect(cuerpo.palabras).toEqual([]);
        expect(cuerpo.total).toBe(total);
        expect(cuerpo.pagina).toBe(99);
      });

      it('400 si limite excede el tope de RNF-12 (50)', async () => {
        const facil = await nivelPorNombre('Fácil');
        await request(app.getHttpServer())
          .get(`/niveles/${facil.id}/palabras`)
          .query({ limite: 51 })
          .expect(400);
      });

      it('400 si pagina o limite no son válidos', async () => {
        const facil = await nivelPorNombre('Fácil');
        await request(app.getHttpServer())
          .get(`/niveles/${facil.id}/palabras`)
          .query({ pagina: 0 })
          .expect(400);
        await request(app.getHttpServer())
          .get(`/niveles/${facil.id}/palabras`)
          .query({ limite: 'abc' })
          .expect(400);
      });

      it('un nivel inexistente sigue dando 404 aun con parámetros de paginación', async () => {
        const respuesta = await request(app.getHttpServer())
          .get('/niveles/999999/palabras')
          .query({ pagina: 2, limite: 10 })
          .expect(404);
        expect(respuesta.body.error.code).toBe('NIVEL_NO_ENCONTRADO');
      });
    });
  });

  describe('GET /niveles/:id/descarga', () => {
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

    // RF-31: mismo estado real del catálogo que T-021 documenta — sin
    // contenido capturado (T-003 bloqueado), ninguna palabra tiene
    // completa=true todavía, así que el paquete viene con la lista vacía.
    // Es el resultado correcto, no un síntoma de endpoint roto.
    it('con el catálogo real (sin recálculo de completa todavía) regresa el nivel con palabras: []', async () => {
      const facil = await nivelPorNombre('Fácil');

      const respuesta = await request(app.getHttpServer())
        .get(`/niveles/${facil.id}/descarga`)
        .expect(200);

      expect(respuesta.body).toEqual({
        nivel: { id: facil.id, nombre: 'Fácil', orden: 1 },
        palabras: [],
      });
    });

    it('incluye texto, significado, oración y url_audio solo de las palabras completa=true AND oculta=false del nivel pedido', async () => {
      const facil = await nivelPorNombre('Fácil');
      const intermedio = await nivelPorNombre('Intermedio');
      const idProfesor = await idProfesorAutor();

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
        .get(`/niveles/${facil.id}/descarga`)
        .expect(200);

      expect(respuesta.body).toEqual({
        nivel: { id: facil.id, nombre: 'Fácil', orden: 1 },
        palabras: [
          {
            id: visible.id,
            texto: visible.texto,
            significado_es: 'significado de prueba',
            oracion_ejemplo: 'An example sentence.',
            url_audio: '/assets/audios/x.mp3',
          },
        ],
      });
    });

    it('404 con mensaje en español si el nivel no existe', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/niveles/999999/descarga')
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
        .get('/niveles/abc/descarga')
        .expect(400);

      expect(respuesta.body).toEqual({
        error: {
          code: 'NIVEL_ID_INVALIDO',
          message: 'El id de nivel debe ser un número entero positivo.',
        },
      });
    });

    it('400 (no 500) si el id es un número demasiado grande para un entero de 64 bits', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/niveles/999999999999999999999/descarga')
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
        .get(`/niveles/${facil.id}/descarga`)
        .expect(200);
    });
  });
});

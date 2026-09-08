import { readdir, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import bcrypt from 'bcrypt';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const CARPETA_AUDIOS = join(process.cwd(), 'assets', 'audios');

const PREFIJO_PRUEBA = 'TEST-T024-';
const PASSWORD = 'ClaveDePrueba123';

const USUARIO_PROFESOR_A = `${PREFIJO_PRUEBA}PROFESOR-A`;
const USUARIO_PROFESOR_B = `${PREFIJO_PRUEBA}PROFESOR-B`;
const USUARIO_ALUMNO = `${PREFIJO_PRUEBA}ALUMNO`;

describe('AdminPalabrasController (e2e) - /admin/palabras', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idNivel: number;
  let idOtroNivel: number;
  let tokenProfesorA: string;
  let tokenProfesorB: string;
  let tokenAlumno: string;
  let idProfesorA: number;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    const facil = await prisma.nivel.findFirst({ where: { nombre: 'Fácil' } });
    const intermedio = await prisma.nivel.findFirst({
      where: { nombre: 'Intermedio' },
    });
    if (!facil || !intermedio) {
      throw new Error('Faltan niveles del seed — corre el seed antes de las pruebas.');
    }
    idNivel = facil.id;
    idOtroNivel = intermedio.id;

    // Cuentas de prueba propias (mismo patrón que roles-guard.e2e-spec.ts):
    // las 2 cuentas reales de profesor tienen contraseña aleatoria
    // desconocida, así que aquí se crean cuentas con contraseña conocida.
    const profesorA = await prisma.usuario.create({
      data: {
        nombreUsuario: USUARIO_PROFESOR_A,
        contrasenaHash: await bcrypt.hash(PASSWORD, 12),
        rol: 'profesor',
        correoElectronico: 'profesor.a.t024@example.com',
        correoRecuperacion: 'profesor.a.t024@example.com',
        debeCambiarContrasena: false,
      },
    });
    idProfesorA = profesorA.id;
    await prisma.usuario.create({
      data: {
        nombreUsuario: USUARIO_PROFESOR_B,
        contrasenaHash: await bcrypt.hash(PASSWORD, 12),
        rol: 'profesor',
        correoElectronico: 'profesor.b.t024@example.com',
        correoRecuperacion: 'profesor.b.t024@example.com',
        debeCambiarContrasena: false,
      },
    });

    async function login(nombre_usuario: string) {
      const res = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ nombre_usuario, contrasena: PASSWORD })
        .expect(200);
      return res.body.access_token as string;
    }

    tokenProfesorA = await login(USUARIO_PROFESOR_A);
    tokenProfesorB = await login(USUARIO_PROFESOR_B);

    await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: USUARIO_ALUMNO,
        nombre: 'Alumno',
        apellido_paterno: 'De Prueba',
        apellido_materno: 'T024',
        carrera: 'Ingeniería en Desarrollo de Software',
        semestre: 5,
        correo: 'alumno.t024@example.com',
        contrasena: PASSWORD,
        acepto_aviso_privacidad: true,
      })
      .expect(201);
    tokenAlumno = await login(USUARIO_ALUMNO);
  });

  afterEach(async () => {
    // Primero los registros de práctica de prueba: Palabra tiene FK
    // ON DELETE RESTRICT desde RegistroPractica, así que si algún test deja
    // uno (p. ej. el de RF-10 con historial) hay que borrarlo antes de la
    // palabra, sin importar si ese test terminó en éxito o en una aserción
    // fallida a medio camino.
    await prisma.registroPractica.deleteMany({
      where: { palabra: { texto: { startsWith: PREFIJO_PRUEBA } } },
    });

    // Los audios de T-025 quedan en disco real (no mockeado) — hay que
    // borrarlos antes de borrar las filas, si no, quedan huérfanos en
    // assets/audios/ entre corridas de la suite.
    const palabrasConAudio = await prisma.palabra.findMany({
      where: {
        texto: { startsWith: PREFIJO_PRUEBA },
        nombreArchivoAudio: { not: null },
      },
      select: { nombreArchivoAudio: true },
    });
    await Promise.all(
      palabrasConAudio.map((p) =>
        unlink(join(CARPETA_AUDIOS, p.nombreArchivoAudio!)).catch(() => {}),
      ),
    );

    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await prisma.perfilAlumno.deleteMany({
      where: { usuario: { nombreUsuario: USUARIO_ALUMNO } },
    });
    await prisma.usuario.deleteMany({
      where: {
        nombreUsuario: {
          in: [USUARIO_PROFESOR_A, USUARIO_PROFESOR_B, USUARIO_ALUMNO],
        },
      },
    });
    await app.close();
  });

  describe('autorización (RNF-07): las 4 rutas exigen rol profesor', () => {
    it('GET sin sesión → 401', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/palabras')
        .expect(401);
      expect(res.body.error.code).toBe('SESION_REQUERIDA');
    });

    it('GET con alumno → 403', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/palabras')
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .expect(403);
      expect(res.body.error.code).toBe('ADMIN_SOLO_PROFESOR');
    });

    it('POST sin sesión → 401', async () => {
      await request(app.getHttpServer())
        .post('/admin/palabras')
        .send({ texto: `${PREFIJO_PRUEBA}x`, id_nivel: idNivel })
        .expect(401);
    });

    it('POST con alumno → 403', async () => {
      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .send({ texto: `${PREFIJO_PRUEBA}x`, id_nivel: idNivel })
        .expect(403);
    });

    it('PATCH :id sin sesión → 401, con alumno → 403', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}auth`, idNivel, idProfesorAutor: idProfesorA },
      });

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .send({ texto: 'x' })
        .expect(401);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .send({ texto: 'x' })
        .expect(403);
    });

    it('PATCH :id/ocultar sin sesión → 401, con alumno → 403', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}auth-ocultar`, idNivel, idProfesorAutor: idProfesorA },
      });

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .send({ oculta: true })
        .expect(401);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .send({ oculta: true })
        .expect(403);
    });
  });

  describe('GET /admin/palabras (RF-39)', () => {
    it('lista TODAS las palabras, completas e incompletas, ocultas y visibles', async () => {
      const incompleta = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}incompleta`, idNivel, idProfesorAutor: idProfesorA },
      });
      const completa = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}completa`,
          idNivel,
          idProfesorAutor: idProfesorA,
          significadoEs: 'significado',
          oracionEjemplo: 'An example sentence.',
          nombreArchivoAudio: '1.mp3',
        },
      });
      const oculta = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}oculta`,
          idNivel,
          idProfesorAutor: idProfesorA,
          oculta: true,
        },
      });

      const respuesta = await request(app.getHttpServer())
        .get('/admin/palabras')
        .query({ limite: 50 })
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(200);

      const ids = respuesta.body.palabras.map((p: { id: number }) => p.id);
      expect(ids).toEqual(
        expect.arrayContaining([incompleta.id, completa.id, oculta.id]),
      );

      const filaCompleta = respuesta.body.palabras.find(
        (p: { id: number }) => p.id === completa.id,
      );
      expect(filaCompleta).toEqual({
        id: completa.id,
        texto: `${PREFIJO_PRUEBA}completa`,
        id_nivel: idNivel,
        significado_es: 'significado',
        oracion_ejemplo: 'An example sentence.',
        url_audio: '/assets/audios/1.mp3',
        completa: true,
        oculta: false,
        fecha_alta: expect.any(String),
        id_profesor_autor: idProfesorA,
      });

      const filaIncompleta = respuesta.body.palabras.find(
        (p: { id: number }) => p.id === incompleta.id,
      );
      expect(filaIncompleta.completa).toBe(false);

      const filaOculta = respuesta.body.palabras.find(
        (p: { id: number }) => p.id === oculta.id,
      );
      expect(filaOculta.oculta).toBe(true);
    });

    it('pagina correctamente y regresa metadatos de paginación', async () => {
      for (let i = 0; i < 5; i++) {
        await prisma.palabra.create({
          data: {
            texto: `${PREFIJO_PRUEBA}pagina-${i}`,
            idNivel,
            idProfesorAutor: idProfesorA,
          },
        });
      }

      const pagina1 = await request(app.getHttpServer())
        .get('/admin/palabras')
        .query({ pagina: 1, limite: 2 })
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(200);
      expect(pagina1.body.palabras).toHaveLength(2);
      expect(pagina1.body.pagina).toBe(1);
      expect(pagina1.body.limite).toBe(2);
      expect(pagina1.body.total).toBeGreaterThanOrEqual(5);

      const pagina2 = await request(app.getHttpServer())
        .get('/admin/palabras')
        .query({ pagina: 2, limite: 2 })
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(200);
      expect(pagina2.body.palabras).toHaveLength(2);

      const idsPagina1 = pagina1.body.palabras.map((p: { id: number }) => p.id);
      const idsPagina2 = pagina2.body.palabras.map((p: { id: number }) => p.id);
      expect(idsPagina1).not.toEqual(idsPagina2);
    });

    it('sin query params, usa una página por defecto (no trae todo de una vez)', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(200);

      expect(respuesta.body.pagina).toBe(1);
      expect(respuesta.body.palabras.length).toBeLessThanOrEqual(
        respuesta.body.limite,
      );
    });

    it('400 si limite excede el tope de RNF-12 (50)', async () => {
      await request(app.getHttpServer())
        .get('/admin/palabras')
        .query({ limite: 51 })
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(400);
    });

    it('400 si pagina o limite no son válidos', async () => {
      await request(app.getHttpServer())
        .get('/admin/palabras')
        .query({ pagina: 0 })
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(400);

      await request(app.getHttpServer())
        .get('/admin/palabras')
        .query({ limite: 'abc' })
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(400);
    });
  });

  describe('POST /admin/palabras (RF-08)', () => {
    it('crea con solo texto + id_nivel; completa=false y el resto en null', async () => {
      const respuesta = await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}minima`, id_nivel: idNivel })
        .expect(201);

      expect(respuesta.body).toEqual({
        id: expect.any(Number),
        texto: `${PREFIJO_PRUEBA}minima`,
        id_nivel: idNivel,
        significado_es: null,
        oracion_ejemplo: null,
        url_audio: null,
        completa: false,
        oculta: false,
        fecha_alta: expect.any(String),
        id_profesor_autor: idProfesorA,
      });
    });

    it('id_profesor_autor se toma del JWT, no del body (no se puede falsificar)', async () => {
      const respuesta = await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorB}`)
        .send({ texto: `${PREFIJO_PRUEBA}autoria`, id_nivel: idNivel })
        .expect(201);

      expect(respuesta.body.id_profesor_autor).not.toBe(idProfesorA);
    });

    it('con significado_es y oracion_ejemplo, sigue completa=false hasta que también tenga audio', async () => {
      const respuesta = await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({
          texto: `${PREFIJO_PRUEBA}parcial`,
          id_nivel: idNivel,
          significado_es: 'significado',
          oracion_ejemplo: 'An example sentence.',
        })
        .expect(201);

      expect(respuesta.body.completa).toBe(false);
      expect(respuesta.body.significado_es).toBe('significado');
    });

    it('400 si falta texto', async () => {
      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ id_nivel: idNivel })
        .expect(400);
    });

    it('400 si falta id_nivel', async () => {
      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}sin-nivel` })
        .expect(400);
    });

    it('404 (no 500) si id_nivel no existe', async () => {
      const respuesta = await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}nivel-fantasma`, id_nivel: 999999 })
        .expect(404);

      expect(respuesta.body.error.code).toBe('NIVEL_NO_ENCONTRADO');
    });

    it('400 si se intenta fijar completa, oculta, nombre_archivo_audio o id_profesor_autor a mano', async () => {
      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}x`, id_nivel: idNivel, completa: true })
        .expect(400);

      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}x`, id_nivel: idNivel, oculta: true })
        .expect(400);

      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({
          texto: `${PREFIJO_PRUEBA}x`,
          id_nivel: idNivel,
          nombre_archivo_audio: '1.mp3',
        })
        .expect(400);

      await request(app.getHttpServer())
        .post('/admin/palabras')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({
          texto: `${PREFIJO_PRUEBA}x`,
          id_nivel: idNivel,
          id_profesor_autor: idProfesorA,
        })
        .expect(400);
    });
  });

  describe('PATCH /admin/palabras/:id (RF-09)', () => {
    it('edita el texto', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}original`, idNivel, idProfesorAutor: idProfesorA },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}editado` })
        .expect(200);

      expect(respuesta.body.texto).toBe(`${PREFIJO_PRUEBA}editado`);
    });

    it('un profesor distinto al autor puede editar (catálogo compartido, sin propiedad individual)', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}de-a`, idNivel, idProfesorAutor: idProfesorA },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorB}`)
        .send({ texto: `${PREFIJO_PRUEBA}editado-por-b` })
        .expect(200);

      expect(respuesta.body.texto).toBe(`${PREFIJO_PRUEBA}editado-por-b`);
      // Editar no reasigna la autoría original.
      expect(respuesta.body.id_profesor_autor).toBe(idProfesorA);
    });

    it('PATCH parcial: no toca los campos que no vienen en el body', async () => {
      const palabra = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}parcial-edit`,
          idNivel,
          idProfesorAutor: idProfesorA,
          significadoEs: 'significado original',
        },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oracion_ejemplo: 'An example sentence.' })
        .expect(200);

      expect(respuesta.body.significado_es).toBe('significado original');
      expect(respuesta.body.oracion_ejemplo).toBe('An example sentence.');
    });

    it('significado_es: null borra el valor ya capturado (y puede volver a completa=false)', async () => {
      const palabra = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}se-borra`,
          idNivel,
          idProfesorAutor: idProfesorA,
          significadoEs: 'significado',
          oracionEjemplo: 'An example sentence.',
          nombreArchivoAudio: '1.mp3',
        },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ significado_es: null })
        .expect(200);

      expect(respuesta.body.significado_es).toBeNull();
      expect(respuesta.body.completa).toBe(false);
    });

    it('cambiar el nivel actualiza id_nivel', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}cambia-nivel`, idNivel, idProfesorAutor: idProfesorA },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ id_nivel: idOtroNivel })
        .expect(200);

      expect(respuesta.body.id_nivel).toBe(idOtroNivel);
    });

    it('404 (no 500) si el nuevo id_nivel no existe', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}nivel-invalido`, idNivel, idProfesorAutor: idProfesorA },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ id_nivel: 999999 })
        .expect(404);

      expect(respuesta.body.error.code).toBe('NIVEL_NO_ENCONTRADO');
    });

    it('404 con mensaje en español si la palabra no existe', async () => {
      const respuesta = await request(app.getHttpServer())
        .patch('/admin/palabras/999999')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: 'x' })
        .expect(404);

      expect(respuesta.body).toEqual({
        error: {
          code: 'PALABRA_NO_ENCONTRADA',
          message: 'No existe una palabra con ese id.',
        },
      });
    });

    it('400 con mensaje en español si el id no es numérico', async () => {
      await request(app.getHttpServer())
        .patch('/admin/palabras/abc')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: 'x' })
        .expect(400);
    });

    it('400 si se intenta editar completa, oculta, nombre_archivo_audio o id_profesor_autor', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}campos-prohibidos`, idNivel, idProfesorAutor: idProfesorA },
      });

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ completa: true })
        .expect(400);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: true })
        .expect(400);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ nombre_archivo_audio: '1.mp3' })
        .expect(400);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ id_profesor_autor: idProfesorA })
        .expect(400);
    });
  });

  describe('PATCH /admin/palabras/:id/ocultar (RF-10)', () => {
    it('oculta y luego desoculta (reversible)', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}toggle`, idNivel, idProfesorAutor: idProfesorA },
      });

      const ocultada = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: true })
        .expect(200);
      expect(ocultada.body.oculta).toBe(true);

      const visible = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: false })
        .expect(200);
      expect(visible.body.oculta).toBe(false);
    });

    it('no borra ni modifica ningún otro campo', async () => {
      const palabra = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}intacta`,
          idNivel,
          idProfesorAutor: idProfesorA,
          significadoEs: 'significado',
          oracionEjemplo: 'An example sentence.',
          nombreArchivoAudio: '1.mp3',
        },
      });

      const respuesta = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: true })
        .expect(200);

      expect(respuesta.body.texto).toBe(`${PREFIJO_PRUEBA}intacta`);
      expect(respuesta.body.significado_es).toBe('significado');
      expect(respuesta.body.oracion_ejemplo).toBe('An example sentence.');
      expect(respuesta.body.completa).toBe(true);
    });

    it('404 si la palabra no existe', async () => {
      await request(app.getHttpServer())
        .patch('/admin/palabras/999999/ocultar')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: true })
        .expect(404);
    });

    // RF-10, criterio literal del ERS: "Ocultar una palabra no elimina
    // ninguno de sus datos ni afecta los registros de práctica que los
    // alumnos ya generaron para ella, los cuales se conservan íntegros".
    // RegistroPractica todavía no tiene endpoint propio (Fase 4) — se crea
    // el registro directo por Prisma, exactamente como lo haría ese futuro
    // endpoint, para probar que ocultar/desocultar no lo toca ni lo borra.
    it('no borra ni modifica los registros de práctica ya generados para la palabra', async () => {
      const alumno = await prisma.usuario.findUnique({
        where: { nombreUsuario: USUARIO_ALUMNO },
      });
      if (!alumno) throw new Error('No se encontró el alumno de prueba.');

      const palabra = await prisma.palabra.create({
        data: {
          texto: `${PREFIJO_PRUEBA}con-historial`,
          idNivel,
          idProfesorAutor: idProfesorA,
          significadoEs: 'significado',
          oracionEjemplo: 'An example sentence.',
          nombreArchivoAudio: '1.mp3',
        },
      });
      const registro = await prisma.registroPractica.create({
        data: {
          idAlumno: alumno.id,
          idPalabra: palabra.id,
          idNivelEnPractica: idNivel,
          tiempoSegundos: 42,
          oracionAlumno: 'I practiced this example sentence.',
          deletreoCorrecto: true,
          sincronizado: true,
        },
      });

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: true })
        .expect(200);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: false })
        .expect(200);

      const registroTrasOcultar = await prisma.registroPractica.findUnique({
        where: { id: registro.id },
      });
      expect(registroTrasOcultar).toEqual(registro);
    });

    it('400 si oculta falta o no es booleano', async () => {
      const palabra = await prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}sin-oculta`, idNivel, idProfesorAutor: idProfesorA },
      });

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({})
        .expect(400);

      await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}/ocultar`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ oculta: 'si' })
        .expect(400);
    });
  });

  describe('POST /admin/palabras/:id/audio (RF-11)', () => {
    async function crearPalabraDePrueba(texto: string) {
      return prisma.palabra.create({
        data: { texto: `${PREFIJO_PRUEBA}${texto}`, idNivel, idProfesorAutor: idProfesorA },
      });
    }

    it('sin sesión → 401, con alumno → 403', async () => {
      const palabra = await crearPalabraDePrueba('audio-auth');

      await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .attach('audio', Buffer.alloc(1000), 'prueba.mp3')
        .expect(401);

      await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .attach('audio', Buffer.alloc(1000), 'prueba.mp3')
        .expect(403);
    });

    it('un archivo fuera de formato se rechaza con mensaje claro', async () => {
      const palabra = await crearPalabraDePrueba('formato-invalido');

      const respuesta = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'grabacion.wav')
        .expect(400);

      expect(respuesta.body).toEqual({
        error: {
          code: 'AUDIO_FORMATO_INVALIDO',
          message: 'El archivo debe ser MP3, AAC o M4A.',
        },
      });

      const enBd = await prisma.palabra.findUnique({ where: { id: palabra.id } });
      expect(enBd?.nombreArchivoAudio).toBeNull();
    });

    it('un archivo que excede 1 MB se rechaza con mensaje claro', async () => {
      const palabra = await crearPalabraDePrueba('demasiado-grande');
      const unMegaMasUnByte = 1024 * 1024 + 1;

      const respuesta = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(unMegaMasUnByte), 'grabacion.mp3')
        .expect(400);

      expect(respuesta.body).toEqual({
        error: {
          code: 'AUDIO_TAMANO_INVALIDO',
          message: 'El archivo no puede pesar más de 1 MB.',
        },
      });

      const enBd = await prisma.palabra.findUnique({ where: { id: palabra.id } });
      expect(enBd?.nombreArchivoAudio).toBeNull();
    });

    it('exactamente 1 MB sí se acepta (el límite es "más de 1 MB", no "1 MB o más")', async () => {
      const palabra = await crearPalabraDePrueba('exacto-1mb');
      const unMegaExacto = 1024 * 1024;

      await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(unMegaExacto), 'grabacion.mp3')
        .expect(201);
    });

    it('un archivo válido queda disponible para reproducirse en url_audio', async () => {
      const palabra = await crearPalabraDePrueba('reproducible');
      const contenido = Buffer.alloc(2000, 'a');

      const subida = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', contenido, 'grabacion.mp3')
        .expect(201);

      expect(subida.body.url_audio).toBe(`/assets/audios/${palabra.id}.mp3`);

      // No basta con el campo derivado de la respuesta: se confirma la
      // columna real en la base de datos, directo por Prisma.
      const enBd = await prisma.palabra.findUniqueOrThrow({
        where: { id: palabra.id },
      });
      expect(enBd.nombreArchivoAudio).toBe(`${palabra.id}.mp3`);

      // "Disponible para reproducirse" de verdad: se descarga por HTTP la
      // misma url que regresó el endpoint y se compara byte a byte, no solo
      // que el campo de la base de datos se haya actualizado.
      const descarga = await request(app.getHttpServer())
        .get(subida.body.url_audio)
        .expect(200);
      expect(Buffer.compare(descarga.body, contenido)).toBe(0);
    });

    it('acepta también .aac y .m4a, no solo .mp3', async () => {
      const palabraAac = await crearPalabraDePrueba('formato-aac');
      const respuestaAac = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabraAac.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'grabacion.aac')
        .expect(201);
      expect(respuestaAac.body.url_audio).toBe(`/assets/audios/${palabraAac.id}.aac`);

      const palabraM4a = await crearPalabraDePrueba('formato-m4a');
      const respuestaM4a = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabraM4a.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'grabacion.m4a')
        .expect(201);
      expect(respuestaM4a.body.url_audio).toBe(`/assets/audios/${palabraM4a.id}.m4a`);
    });

    it('nombra el archivo por el id, nunca por el texto de la palabra', async () => {
      const palabra = await crearPalabraDePrueba('nombre-por-id');

      const respuesta = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'grabacion.mp3')
        .expect(201);

      expect(respuesta.body.url_audio).toBe(`/assets/audios/${palabra.id}.mp3`);
      expect(respuesta.body.url_audio).not.toContain(palabra.texto);

      // Directo en la base de datos, no solo en la respuesta derivada.
      const enBd = await prisma.palabra.findUniqueOrThrow({
        where: { id: palabra.id },
      });
      expect(enBd.nombreArchivoAudio).toBe(`${palabra.id}.mp3`);

      // Directo en el sistema de archivos real: existe <id>.mp3 y NINGÚN
      // archivo en la carpeta se llama a partir del texto de la palabra.
      const archivosEnDisco = await readdir(CARPETA_AUDIOS);
      expect(archivosEnDisco).toContain(`${palabra.id}.mp3`);
      expect(
        archivosEnDisco.some((nombre) => nombre.includes(palabra.texto)),
      ).toBe(false);
    });

    it('reemplazar el audio con otra extensión borra el archivo viejo del disco', async () => {
      const palabra = await crearPalabraDePrueba('reemplazo');

      await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'primero.mp3')
        .expect(201);

      const segunda = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'segundo.m4a')
        .expect(201);

      expect(segunda.body.url_audio).toBe(`/assets/audios/${palabra.id}.m4a`);

      // El .mp3 viejo ya no debe existir ni servirse.
      await request(app.getHttpServer())
        .get(`/assets/audios/${palabra.id}.mp3`)
        .expect(404);
      // El .m4a nuevo sí.
      await request(app.getHttpServer())
        .get(`/assets/audios/${palabra.id}.m4a`)
        .expect(200);
    });

    it('editar el texto de la palabra después no desvincula su audio', async () => {
      const palabra = await crearPalabraDePrueba('no-se-desvincula');
      const subida = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'grabacion.mp3')
        .expect(201);

      const editada = await request(app.getHttpServer())
        .patch(`/admin/palabras/${palabra.id}`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .send({ texto: `${PREFIJO_PRUEBA}texto-nuevo-tras-audio` })
        .expect(200);

      expect(editada.body.url_audio).toBe(subida.body.url_audio);
      await request(app.getHttpServer()).get(editada.body.url_audio).expect(200);
    });

    it('404 (no 500) si la palabra no existe', async () => {
      const respuesta = await request(app.getHttpServer())
        .post('/admin/palabras/999999/audio')
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .attach('audio', Buffer.alloc(1000), 'grabacion.mp3')
        .expect(404);

      expect(respuesta.body.error.code).toBe('PALABRA_NO_ENCONTRADA');
    });

    it('400 con mensaje claro si no se adjunta ningún archivo', async () => {
      const palabra = await crearPalabraDePrueba('sin-archivo');

      const respuesta = await request(app.getHttpServer())
        .post(`/admin/palabras/${palabra.id}/audio`)
        .set('Authorization', `Bearer ${tokenProfesorA}`)
        .expect(400);

      expect(respuesta.body).toEqual({
        error: {
          code: 'AUDIO_FALTANTE',
          message: 'Debes adjuntar un archivo de audio.',
        },
      });
    });
  });
});

import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

// T-047 (RF-24). La insignia se OTORGA como efecto de POST /practica (nunca
// por su cuenta) cuando ese intento deja al alumno con al menos un registro
// de práctica para TODAS las palabras completas y visibles del nivel — el
// mismo conjunto que RF-06 le muestra al alumno para practicar (ver
// NivelesService.listarPalabras) — y se LEE con GET /progreso/insignias.
describe('InsigniasController (e2e) - GET /progreso/insignias + insignia vía POST /practica', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idNivel: number;
  let nombreNivel: string;
  let idNivelFacil: number;
  let idProfesorAutor: number;
  let idPalabra1: number;
  let idPalabra2: number;
  let idPalabraFacil: number;
  let tokenAlumno: string;
  let tokenOtroAlumno: string;

  const PREFIJO_PRUEBA = 'TEST-T047-';
  const USUARIO_ALUMNO = 'TEST-T047-ALUMNO';
  const USUARIO_OTRO_ALUMNO = 'TEST-T047-OTRO-ALUMNO';
  const PASSWORD = 'ClaveDePrueba123';
  const FECHA = '2026-09-11';

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    const nivel = await prisma.nivel.findFirst({ where: { nombre: 'Difícil' } });
    const nivelFacil = await prisma.nivel.findFirst({ where: { nombre: 'Fácil' } });
    const profesor = await prisma.usuario.findUnique({
      where: { nombreUsuario: 'profesorIngles' },
    });
    if (!nivel || !nivelFacil || !profesor) {
      throw new Error(
        'Faltan datos de seed (niveles "Difícil"/"Fácil" o "profesorIngles") — corre el seed antes de las pruebas.',
      );
    }
    idNivel = nivel.id;
    nombreNivel = nivel.nombre;
    idNivelFacil = nivelFacil.id;
    idProfesorAutor = profesor.id;

    // El "universo" a completar del nivel Difícil: exactamente 2 palabras
    // completas y visibles.
    const p1 = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}uno`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado uno',
        oracionEjemplo: 'This is example one.',
        nombreArchivoAudio: 'test-t047-uno.mp3',
      },
    });
    idPalabra1 = p1.id;
    const p2 = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}dos`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'significado dos',
        oracionEjemplo: 'This is example two.',
        nombreArchivoAudio: 'test-t047-dos.mp3',
      },
    });
    idPalabra2 = p2.id;

    // Palabra INCOMPLETA (sin significado/oración/audio) del mismo nivel:
    // no debe exigirse practicarla para llegar al 100% (RF-06/RF-24 solo
    // cuentan palabras completas).
    await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}incompleta`, idNivel, idProfesorAutor },
    });

    // Palabra completa pero OCULTA del mismo nivel: tampoco debe exigirse
    // (RF-10/RF-24).
    await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}oculta`,
        idNivel,
        idProfesorAutor,
        significadoEs: 'x',
        oracionEjemplo: 'x.',
        nombreArchivoAudio: 'test-t047-oculta.mp3',
        oculta: true,
      },
    });

    // Una sola palabra completa y visible en Fácil, para la prueba de orden
    // de GET /progreso/insignias con más de un nivel completado.
    const pFacil = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}facil`,
        idNivel: idNivelFacil,
        idProfesorAutor,
        significadoEs: 'x',
        oracionEjemplo: 'x.',
        nombreArchivoAudio: 'test-t047-facil.mp3',
      },
    });
    idPalabraFacil = pFacil.id;

    async function registrarYObtenerId(matricula: string): Promise<number> {
      const res = await request(app.getHttpServer())
        .post('/auth/registro')
        .send({
          matricula,
          nombre: 'Alumna',
          apellido_paterno: 'De',
          apellido_materno: 'Prueba',
          carrera: 'Ingeniería en Desarrollo de Software',
          semestre: 4,
          correo: `${matricula.toLowerCase()}@example.com`,
          contrasena: PASSWORD,
          acepto_aviso_privacidad: true,
        })
        .expect(201);
      return res.body.id as number;
    }

    async function login(nombre_usuario: string): Promise<string> {
      const res = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ nombre_usuario, contrasena: PASSWORD })
        .expect(200);
      return res.body.access_token as string;
    }

    await registrarYObtenerId(USUARIO_ALUMNO);
    await registrarYObtenerId(USUARIO_OTRO_ALUMNO);
    tokenAlumno = await login(USUARIO_ALUMNO);
    tokenOtroAlumno = await login(USUARIO_OTRO_ALUMNO);
  });

  afterEach(async () => {
    await prisma.insignia.deleteMany({
      where: {
        alumno: { nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO] } },
      },
    });
    await prisma.registroPractica.deleteMany({
      where: { palabra: { texto: { startsWith: PREFIJO_PRUEBA } } },
    });
    await prisma.racha.deleteMany({
      where: {
        alumno: { nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO] } },
      },
    });
    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await prisma.perfilAlumno.deleteMany({
      where: {
        usuario: { nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO] } },
      },
    });
    await prisma.usuario.deleteMany({
      where: { nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO] } },
    });
    await app.close();
  });

  async function practicar(token: string, idPalabra: number) {
    return request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${token}`)
      .send({
        id_palabra: idPalabra,
        tiempo_segundos: 10,
        oracion_alumno: 'A test sentence.',
        deletreo_correcto: true,
        fecha_local: FECHA,
      })
      .expect(201);
  }

  async function obtenerInsignias(token: string) {
    return request(app.getHttpServer())
      .get('/progreso/insignias')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
  }

  it('un alumno que nunca practicó no tiene insignias', async () => {
    const respuesta = await obtenerInsignias(tokenAlumno);
    expect(respuesta.body).toEqual([]);
  });

  it('practicar solo ALGUNAS de las palabras completas del nivel no otorga insignia', async () => {
    const r1 = await practicar(tokenAlumno, idPalabra1);
    expect(r1.body.insignia_otorgada).toBeNull();

    const insignias = await obtenerInsignias(tokenAlumno);
    expect(insignias.body).toEqual([]);
  });

  it('RF-24: practicar TODAS las palabras completas y visibles del nivel otorga la insignia en ese mismo intento', async () => {
    const r1 = await practicar(tokenAlumno, idPalabra1);
    expect(r1.body.insignia_otorgada).toBeNull();

    const r2 = await practicar(tokenAlumno, idPalabra2);
    expect(r2.body.insignia_otorgada).toEqual({
      id_nivel: idNivel,
      nombre_nivel: nombreNivel,
      fecha_otorgada: expect.any(String),
    });

    const insignias = await obtenerInsignias(tokenAlumno);
    expect(insignias.body).toEqual([
      { id_nivel: idNivel, nombre_nivel: nombreNivel, fecha_otorgada: expect.any(String) },
    ]);
  });

  it('una palabra incompleta o una oculta del nivel NO cuentan para el 100% — 2 completas y visibles bastan', async () => {
    await practicar(tokenAlumno, idPalabra1);
    const r2 = await practicar(tokenAlumno, idPalabra2);
    expect(r2.body.insignia_otorgada).not.toBeNull();
  });

  it('practicar la MISMA palabra varias veces no sustituye practicar la otra', async () => {
    await practicar(tokenAlumno, idPalabra1);
    await practicar(tokenAlumno, idPalabra1);
    const r = await practicar(tokenAlumno, idPalabra1);
    expect(r.body.insignia_otorgada).toBeNull();
  });

  it('la insignia es permanente: no se vuelve a otorgar ni a recalcular en intentos posteriores', async () => {
    await practicar(tokenAlumno, idPalabra1);
    const r2 = await practicar(tokenAlumno, idPalabra2);
    expect(r2.body.insignia_otorgada).not.toBeNull();

    const r3 = await practicar(tokenAlumno, idPalabra1);
    expect(r3.body.insignia_otorgada).toBeNull();

    const insignias = await obtenerInsignias(tokenAlumno);
    expect(insignias.body.length).toBe(1);
  });

  it('GET /progreso/insignias ordena por el orden fijo del nivel (RF-05), sin importar en qué orden se ganaron', async () => {
    // Se completa primero Difícil y despupés Fácil — el orden de la
    // respuesta debe seguir siendo Fácil antes que Difícil (orden=1 antes
    // que orden=3), no el orden en que se otorgaron.
    await practicar(tokenAlumno, idPalabra1);
    await practicar(tokenAlumno, idPalabra2);
    await practicar(tokenAlumno, idPalabraFacil);

    const insignias = await obtenerInsignias(tokenAlumno);
    expect(insignias.body).toEqual([
      { id_nivel: idNivelFacil, nombre_nivel: 'Fácil', fecha_otorgada: expect.any(String) },
      { id_nivel: idNivel, nombre_nivel: nombreNivel, fecha_otorgada: expect.any(String) },
    ]);
  });

  it('RNF-08 implícito: la insignia de un alumno no se mezcla con la de otro', async () => {
    await practicar(tokenAlumno, idPalabra1);
    await practicar(tokenAlumno, idPalabra2);

    const insigniasOtro = await obtenerInsignias(tokenOtroAlumno);
    expect(insigniasOtro.body).toEqual([]);

    const insigniasAlumno = await obtenerInsignias(tokenAlumno);
    expect(insigniasAlumno.body.length).toBe(1);
  });

  it('requiere sesión iniciada', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/progreso/insignias')
      .expect(401);

    expect(respuesta.body.error.code).toBe('SESION_REQUERIDA');
  });
});

import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const PREFIJO_PRUEBA = 'TEST-T042-';

describe('PracticaController (e2e) - GET /practica/mejor-tiempo/:idPalabra', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idNivel: number;
  let idProfesorAutor: number;
  let idPalabra: number;
  let idAlumno: number;
  let tokenAlumno: string;
  let tokenOtroAlumno: string;

  const USUARIO_ALUMNO = 'TEST-T042-ALUMNO';
  const USUARIO_OTRO_ALUMNO = 'TEST-T042-OTRO-ALUMNO';
  const PASSWORD = 'ClaveDePrueba123';

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

    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}business`, idNivel, idProfesorAutor },
    });
    idPalabra = palabra.id;

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

    idAlumno = await registrarYObtenerId(USUARIO_ALUMNO);
    await registrarYObtenerId(USUARIO_OTRO_ALUMNO);
    tokenAlumno = await login(USUARIO_ALUMNO);
    tokenOtroAlumno = await login(USUARIO_OTRO_ALUMNO);
  });

  afterEach(async () => {
    await prisma.registroPractica.deleteMany({
      where: { palabra: { texto: { startsWith: PREFIJO_PRUEBA } } },
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

  // T-045 (POST /practica) todavía no existe: hoy no hay NINGÚN registro en
  // la tabla, así que este es el único caso real hasta que exista. La
  // prueba de abajo con datos insertados a mano confirma que, cuando SÍ
  // haya filas (después de T-045), el cálculo del mínimo ya funciona.
  it('regresa null si el alumno no tiene ningún intento previo de esa palabra (caso real de hoy)', async () => {
    const respuesta = await request(app.getHttpServer())
      .get(`/practica/mejor-tiempo/${idPalabra}`)
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(200);

    expect(respuesta.body).toEqual({ mejor_tiempo_segundos: null });
  });

  it('RF-22: regresa el tiempo MÁS BAJO entre varios intentos previos del alumno', async () => {
    for (const tiempoSegundos of [40, 25, 60]) {
      await prisma.registroPractica.create({
        data: {
          idAlumno,
          idPalabra,
          idNivelEnPractica: idNivel,
          tiempoSegundos,
          oracionAlumno: 'This is a good business.',
          deletreoCorrecto: true,
          sincronizado: true,
        },
      });
    }

    const respuesta = await request(app.getHttpServer())
      .get(`/practica/mejor-tiempo/${idPalabra}`)
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(200);

    expect(respuesta.body).toEqual({ mejor_tiempo_segundos: 25 });
  });

  it('RNF-08 implícito: no cuenta los intentos de OTRO alumno para la misma palabra', async () => {
    await prisma.registroPractica.create({
      data: {
        idAlumno, // el otro alumno, no el que pregunta
        idPalabra,
        idNivelEnPractica: idNivel,
        tiempoSegundos: 5,
        oracionAlumno: 'This is a good business.',
        deletreoCorrecto: true,
        sincronizado: true,
      },
    });

    const respuesta = await request(app.getHttpServer())
      .get(`/practica/mejor-tiempo/${idPalabra}`)
      .set('Authorization', `Bearer ${tokenOtroAlumno}`)
      .expect(200);

    expect(respuesta.body).toEqual({ mejor_tiempo_segundos: null });
  });

  it('no cuenta intentos del mismo alumno en OTRA palabra', async () => {
    const otraPalabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}otra`, idNivel, idProfesorAutor },
    });
    await prisma.registroPractica.create({
      data: {
        idAlumno,
        idPalabra: otraPalabra.id,
        idNivelEnPractica: idNivel,
        tiempoSegundos: 5,
        oracionAlumno: 'An example.',
        deletreoCorrecto: true,
        sincronizado: true,
      },
    });

    const respuesta = await request(app.getHttpServer())
      .get(`/practica/mejor-tiempo/${idPalabra}`)
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(200);

    expect(respuesta.body).toEqual({ mejor_tiempo_segundos: null });
  });

  it('requiere sesión iniciada', async () => {
    const respuesta = await request(app.getHttpServer())
      .get(`/practica/mejor-tiempo/${idPalabra}`)
      .expect(401);

    expect(respuesta.body.error.code).toBe('SESION_REQUERIDA');
  });

  it('400 con mensaje en español si el id de palabra no es numérico', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/practica/mejor-tiempo/abc')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(400);

    expect(respuesta.body).toEqual({
      error: {
        code: 'PALABRA_ID_INVALIDO',
        message: 'El id de palabra debe ser un número entero positivo.',
      },
    });
  });
});

import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

// T-046 (RF-23). La racha se ACTUALIZA como efecto de POST /practica (nunca
// por su cuenta — no hay una acción de "solo actualizar racha" sin
// practicar) y se LEE con GET /racha. Todas las fechas de estas pruebas son
// literales "YYYY-MM-DD" que el propio caso de prueba elige — no depende
// del reloj real de la máquina que corre las pruebas en ningún momento,
// exactamente como se supone que debe funcionar: el servidor nunca decide
// qué día es, solo lo que el cliente le manda.
describe('RachaController (e2e) - GET /racha + racha vía POST /practica', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idNivel: number;
  let idProfesorAutor: number;
  let idPalabra: number;
  let idAlumno: number;
  let tokenAlumno: string;
  let tokenOtroAlumno: string;

  const PREFIJO_PRUEBA = 'TEST-T046-';
  const USUARIO_ALUMNO = 'TEST-T046-ALUMNO';
  const USUARIO_OTRO_ALUMNO = 'TEST-T046-OTRO-ALUMNO';
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
      data: { texto: `${PREFIJO_PRUEBA}palabra`, idNivel, idProfesorAutor },
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
    await prisma.racha.deleteMany({
      where: {
        alumno: { nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO] } },
      },
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

  async function practicar(token: string, fecha_local: string) {
    return request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${token}`)
      .send({
        id_palabra: idPalabra,
        tiempo_segundos: 10,
        oracion_alumno: 'A test sentence.',
        deletreo_correcto: true,
        fecha_local,
      })
      .expect(201);
  }

  async function obtenerRacha(token: string, fecha_local: string) {
    return request(app.getHttpServer())
      .get('/racha')
      .query({ fecha_local })
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
  }

  it('un alumno que nunca practicó tiene racha 0', async () => {
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-10');
    expect(respuesta.body).toEqual({ dias_consecutivos: 0 });
  });

  it('RF-23: el primer intento de práctica deja la racha en 1', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-10');
    expect(respuesta.body).toEqual({ dias_consecutivos: 1 });
  });

  it('RF-23: practicar dos días calendario locales consecutivos sube la racha a 2', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    await practicar(tokenAlumno, '2026-09-11');
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-11');
    expect(respuesta.body).toEqual({ dias_consecutivos: 2 });
  });

  it('RF-23: tres días consecutivos suben la racha a 3', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    await practicar(tokenAlumno, '2026-09-11');
    await practicar(tokenAlumno, '2026-09-12');
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-12');
    expect(respuesta.body).toEqual({ dias_consecutivos: 3 });
  });

  it('RF-23: practicar varias veces el MISMO día calendario local no sube la racha', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    await practicar(tokenAlumno, '2026-09-10');
    await practicar(tokenAlumno, '2026-09-10');
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-10');
    expect(respuesta.body).toEqual({ dias_consecutivos: 1 });
  });

  it('RF-23: saltarse un día calendario local completo reinicia la racha (el día que sí practica cuenta como 1, no como el valor viejo + 1)', async () => {
    await practicar(tokenAlumno, '2026-09-10'); // día 1
    await practicar(tokenAlumno, '2026-09-11'); // día 2 (consecutivo) → racha=2
    // Se salta el 12: practica hasta el 13 → el 12 transcurrió completo sin práctica.
    await practicar(tokenAlumno, '2026-09-13');
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-13');
    expect(respuesta.body).toEqual({ dias_consecutivos: 1 });
  });

  it('RF-23: lectura en vivo — un día después del último registro, sin volver a practicar, la racha sigue viva todavía', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    // Es "el día siguiente" (2026-09-11) y el alumno todavía no practica hoy:
    // ese día apenas está en curso, no ha "transcurrido completo" sin práctica.
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-11');
    expect(respuesta.body).toEqual({ dias_consecutivos: 1 });
  });

  it('RF-23: lectura en vivo — dos días después del último registro sin practicar, la racha se muestra en 0 aunque no haya un POST nuevo', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    // Para el 2026-09-12, todo el 2026-09-11 transcurrió sin ningún
    // registro — la racha debe mostrarse rota AUNQUE la fila en la base
    // todavía diga 1 (esa fila solo se corrige de verdad la próxima vez
    // que el alumno practique).
    const respuesta = await obtenerRacha(tokenAlumno, '2026-09-12');
    expect(respuesta.body).toEqual({ dias_consecutivos: 0 });

    const filaCruda = await prisma.racha.findUnique({ where: { idAlumno } });
    expect(filaCruda?.diasConsecutivos).toBe(1);
  });

  it('RNF-08 implícito: la racha de un alumno no se mezcla con la de otro', async () => {
    await practicar(tokenAlumno, '2026-09-10');
    await practicar(tokenAlumno, '2026-09-11');

    const rachaOtro = await obtenerRacha(tokenOtroAlumno, '2026-09-11');
    expect(rachaOtro.body).toEqual({ dias_consecutivos: 0 });

    await practicar(tokenOtroAlumno, '2026-09-11');
    const rachaOtroTrasPracticar = await obtenerRacha(tokenOtroAlumno, '2026-09-11');
    expect(rachaOtroTrasPracticar.body).toEqual({ dias_consecutivos: 1 });

    const rachaOriginal = await obtenerRacha(tokenAlumno, '2026-09-11');
    expect(rachaOriginal.body).toEqual({ dias_consecutivos: 2 });
  });

  it('requiere sesión iniciada', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/racha')
      .query({ fecha_local: '2026-09-10' })
      .expect(401);

    expect(respuesta.body.error.code).toBe('SESION_REQUERIDA');
  });

  it('400 si fecha_local no tiene el formato YYYY-MM-DD', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/racha')
      .query({ fecha_local: '10-09-2026' })
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');
  });

  it('400 si fecha_local es una fecha calendario que no existe (p. ej. 30 de febrero)', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/racha')
      .query({ fecha_local: '2026-02-30' })
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(400);

    expect(respuesta.body.error.code).toBe('FECHA_LOCAL_INVALIDA');
  });

  it('400 en POST /practica si fecha_local no tiene el formato correcto', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({
        id_palabra: idPalabra,
        tiempo_segundos: 10,
        oracion_alumno: 'A test sentence.',
        deletreo_correcto: true,
        fecha_local: 'no-es-una-fecha',
      })
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');
  });
});

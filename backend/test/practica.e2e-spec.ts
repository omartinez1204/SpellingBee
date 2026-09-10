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

describe('PracticaController (e2e) - POST /practica', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idNivelFacil: number;
  let idNivelDificil: number;
  let idProfesorAutor: number;
  let idPalabra: number;
  let idAlumno: number;
  let tokenAlumno: string;

  const PREFIJO_PRUEBA = 'TEST-T045-';
  const USUARIO_ALUMNO = 'TEST-T045-ALUMNO';
  const PASSWORD = 'ClaveDePrueba123';

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    const facil = await prisma.nivel.findFirst({ where: { nombre: 'Fácil' } });
    const dificil = await prisma.nivel.findFirst({ where: { nombre: 'Difícil' } });
    const profesor = await prisma.usuario.findUnique({
      where: { nombreUsuario: 'profesorIngles' },
    });
    if (!facil || !dificil || !profesor) {
      throw new Error(
        'Faltan datos de seed (niveles "Fácil"/"Difícil" o "profesorIngles") — corre el seed antes de las pruebas.',
      );
    }
    idNivelFacil = facil.id;
    idNivelDificil = dificil.id;
    idProfesorAutor = profesor.id;

    const palabra = await prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}collect`, idNivel: idNivelFacil, idProfesorAutor },
    });
    idPalabra = palabra.id;

    const registro = await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: USUARIO_ALUMNO,
        nombre: 'Alumna',
        apellido_paterno: 'De',
        apellido_materno: 'Prueba',
        carrera: 'Ingeniería en Desarrollo de Software',
        semestre: 4,
        correo: `${USUARIO_ALUMNO.toLowerCase()}@example.com`,
        contrasena: PASSWORD,
        acepto_aviso_privacidad: true,
      })
      .expect(201);
    idAlumno = registro.body.id as number;

    const login = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ nombre_usuario: USUARIO_ALUMNO, contrasena: PASSWORD })
      .expect(200);
    tokenAlumno = login.body.access_token as string;
  });

  afterEach(async () => {
    await prisma.registroPractica.deleteMany({
      where: { palabra: { texto: { startsWith: PREFIJO_PRUEBA } } },
    });
    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await prisma.perfilAlumno.deleteMany({
      where: { usuario: { nombreUsuario: USUARIO_ALUMNO } },
    });
    await prisma.usuario.deleteMany({
      where: { nombreUsuario: USUARIO_ALUMNO },
    });
    await app.close();
  });

  const cuerpoValido = () => ({
    id_palabra: idPalabra,
    tiempo_segundos: 42,
    oracion_alumno: 'I will collect the mail today.',
    deletreo_correcto: true,
  });

  it('RF-21/RF-27: guarda el registro y regresa 201 con un id', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send(cuerpoValido())
      .expect(201);

    expect(respuesta.body).toEqual({ id: expect.any(Number) });

    const guardado = await prisma.registroPractica.findUnique({
      where: { id: respuesta.body.id },
    });
    expect(guardado).toMatchObject({
      idAlumno,
      idPalabra,
      tiempoSegundos: 42,
      oracionAlumno: 'I will collect the mail today.',
      deletreoCorrecto: true,
      sincronizado: true,
    });
  });

  it('RF-09: fija id_nivel_en_practica como snapshot del nivel ACTUAL de la palabra, no una referencia viva', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send(cuerpoValido())
      .expect(201);

    const guardadoAntes = await prisma.registroPractica.findUnique({
      where: { id: respuesta.body.id },
    });
    expect(guardadoAntes?.idNivelEnPractica).toBe(idNivelFacil);

    // El profesor cambia la palabra a otro nivel DESPUÉS de este intento.
    await prisma.palabra.update({
      where: { id: idPalabra },
      data: { idNivel: idNivelDificil },
    });

    const guardadoDespues = await prisma.registroPractica.findUnique({
      where: { id: respuesta.body.id },
    });
    expect(guardadoDespues?.idNivelEnPractica).toBe(idNivelFacil);
  });

  it('acepta tiempo_segundos = 0 (Terminé presionado en el mismo segundo que Iniciar)', async () => {
    await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ ...cuerpoValido(), tiempo_segundos: 0 })
      .expect(201);
  });

  it('deletreo_correcto: false y una oración vacía también se guardan tal cual (RF-25/RF-26 no bloquean)', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ ...cuerpoValido(), oracion_alumno: '', deletreo_correcto: false })
      .expect(201);

    const guardado = await prisma.registroPractica.findUnique({
      where: { id: respuesta.body.id },
    });
    expect(guardado).toMatchObject({ oracionAlumno: '', deletreoCorrecto: false });
  });

  it('el registro recién guardado sí cuenta para GET /practica/mejor-tiempo (integración con RF-22)', async () => {
    await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ ...cuerpoValido(), tiempo_segundos: 17 })
      .expect(201);

    const mejorTiempo = await request(app.getHttpServer())
      .get(`/practica/mejor-tiempo/${idPalabra}`)
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .expect(200);

    expect(mejorTiempo.body).toEqual({ mejor_tiempo_segundos: 17 });
  });

  it('requiere sesión iniciada', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .send(cuerpoValido())
      .expect(401);

    expect(respuesta.body.error.code).toBe('SESION_REQUERIDA');
  });

  it('400 si la palabra no existe', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ ...cuerpoValido(), id_palabra: 999999999 })
      .expect(404);

    expect(respuesta.body.error.code).toBe('PALABRA_NO_ENCONTRADA');
  });

  it('400 si falta un campo obligatorio', async () => {
    const { tiempo_segundos: _omitido, ...incompleto } = cuerpoValido();

    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send(incompleto)
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');
  });

  it('400 si tiempo_segundos es negativo', async () => {
    await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ ...cuerpoValido(), tiempo_segundos: -1 })
      .expect(400);
  });

  // RF-27/RF-40: "el sistema no debe subir al backend ni almacenar en la
  // base de datos ningún audio de voz del alumno". No es una promesa que
  // dependa de que el servicio "decida" ignorar el campo: ValidationPipe
  // corre con forbidNonWhitelisted:true (app.config.ts), así que un campo
  // fuera del DTO tumba la petición ENTERA con 400 antes de tocar la base
  // de datos — ni siquiera llega a guardarse el resto de campos válidos.
  it('RF-27/RF-40: rechaza la petición completa si trae cualquier campo de audio, no solo lo ignora', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ ...cuerpoValido(), audio_base64: 'ZmFrZS1hdWRpby1kYXRh' })
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');

    const cuenta = await prisma.registroPractica.count({
      where: { idAlumno, idPalabra },
    });
    expect(cuenta).toBe(0);
  });
});

import { randomUUID } from 'node:crypto';
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
    // T-046/T-047: guardarPractica() ahora también escribe Racha (RF-23) e
    // Insignia (RF-24) como efecto del guardado — sin borrarlas aquí, la
    // siguiente corrida choca con la restricción de llave foránea al
    // intentar borrar el usuario. Ninguna palabra de este archivo es
    // "completa" (T-022), así que hoy nunca se crea una Insignia real aquí
    // — se limpia de todos modos por si algo cambia más adelante.
    await prisma.racha.deleteMany({
      where: { alumno: { nombreUsuario: USUARIO_ALUMNO } },
    });
    await prisma.insignia.deleteMany({
      where: { alumno: { nombreUsuario: USUARIO_ALUMNO } },
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
    // T-046: fecha fija de prueba — la lógica de racha en sí (consecutiva,
    // mismo día, con hueco) se prueba aparte en racha.e2e-spec.ts; aquí
    // solo hace falta un valor válido para no romper la validación del DTO.
    fecha_local: '2026-09-10',
  });

  it('RF-21/RF-27: guarda el registro y regresa 201 con un id', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send(cuerpoValido())
      .expect(201);

    expect(respuesta.body).toEqual({ id: expect.any(Number), insignia_otorgada: null });

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

describe('PracticaController (e2e) - POST /practica/sync', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idNivelFacil: number;
  let idProfesorAutor: number;
  let idPalabra: number;
  let idPalabraCompleta: number;
  let idAlumno: number;
  let tokenAlumno: string;

  const PREFIJO_PRUEBA = 'TEST-T063-';
  const USUARIO_ALUMNO = 'TEST-T063-ALUMNO';
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
    const profesor = await prisma.usuario.findUnique({
      where: { nombreUsuario: 'profesorIngles' },
    });
    if (!facil || !profesor) {
      throw new Error(
        'Faltan datos de seed (nivel "Fácil" o "profesorIngles") — corre el seed antes de las pruebas.',
      );
    }
    idNivelFacil = facil.id;
    idProfesorAutor = profesor.id;

    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}collect`,
        idNivel: idNivelFacil,
        idProfesorAutor,
      },
    });
    idPalabra = palabra.id;

    // Única palabra COMPLETA y visible de Fácil dentro de este bloque (las
    // 45 del catálogo real siguen bloqueadas, T-003) — mismo patrón que
    // insignias.e2e-spec.ts: practicarla basta para completar el 100% de
    // Fácil y probar que sincronizarLote() también otorga la insignia.
    const palabraCompleta = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}complete`,
        idNivel: idNivelFacil,
        idProfesorAutor,
        significadoEs: 'completo',
        oracionEjemplo: 'This word is complete.',
        nombreArchivoAudio: 'test-t063-complete.mp3',
      },
    });
    idPalabraCompleta = palabraCompleta.id;

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
    await prisma.racha.deleteMany({
      where: { alumno: { nombreUsuario: USUARIO_ALUMNO } },
    });
    await prisma.insignia.deleteMany({
      where: { alumno: { nombreUsuario: USUARIO_ALUMNO } },
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

  const registroValido = (overrides: Record<string, unknown> = {}) => ({
    id: randomUUID(),
    id_palabra: idPalabra,
    tiempo_segundos: 10,
    oracion_alumno: 'I will collect the mail today.',
    deletreo_correcto: true,
    fecha_local: '2026-09-10',
    ...overrides,
  });

  it('sincroniza un lote de varios registros nuevos, cada uno con su id de cliente', async () => {
    const registros = [
      registroValido({ id: 'lote-a', tiempo_segundos: 10 }),
      registroValido({ id: 'lote-b', tiempo_segundos: 20 }),
    ];

    const respuesta = await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros })
      .expect(200);

    expect(respuesta.body).toEqual({ sincronizados: 2, ya_existian: 0 });

    const guardados = await prisma.registroPractica.findMany({
      where: { idAlumno },
      orderBy: { tiempoSegundos: 'asc' },
    });
    expect(guardados).toHaveLength(2);
    expect(guardados[0]).toMatchObject({
      idCliente: 'lote-a',
      tiempoSegundos: 10,
      sincronizado: true,
    });
    expect(guardados[1]).toMatchObject({ idCliente: 'lote-b', tiempoSegundos: 20 });
  });

  it('RF-33: idempotente — reenviar el MISMO lote no duplica ni sobreescribe', async () => {
    const registros = [registroValido({ id: 'reintento-1', tiempo_segundos: 30 })];

    await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros })
      .expect(200);

    // Mismo id, tiempo distinto — si esto "sobreescribiera" en vez de
    // saltarse, el tiempo guardado cambiaría a 99; RF-33 exige que no lo haga.
    const segundoIntento = await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros: [registroValido({ id: 'reintento-1', tiempo_segundos: 99 })] })
      .expect(200);

    expect(segundoIntento.body).toEqual({ sincronizados: 0, ya_existian: 1 });

    const guardados = await prisma.registroPractica.findMany({
      where: { idCliente: 'reintento-1' },
    });
    expect(guardados).toHaveLength(1);
    expect(guardados[0].tiempoSegundos).toBe(30);
  });

  it('RF-33: en un lote MIXTO, solo se crean los registros con id nuevo — los ya existentes no se tocan', async () => {
    await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros: [registroValido({ id: 'ya-estaba' })] })
      .expect(200);

    const respuesta = await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({
        registros: [
          registroValido({ id: 'ya-estaba' }),
          registroValido({ id: 'es-nuevo', tiempo_segundos: 55 }),
        ],
      })
      .expect(200);

    expect(respuesta.body).toEqual({ sincronizados: 1, ya_existian: 1 });
    expect(await prisma.registroPractica.count({ where: { idAlumno } })).toBe(2);
  });

  it('RF-23: procesa por fecha_local ASCENDENTE sin importar el orden del arreglo, para no romper la racha', async () => {
    // Mandados fuera de orden (día 3, día 1, día 2) a propósito.
    const registros = [
      registroValido({ id: 'dia-3', fecha_local: '2026-09-12' }),
      registroValido({ id: 'dia-1', fecha_local: '2026-09-10' }),
      registroValido({ id: 'dia-2', fecha_local: '2026-09-11' }),
    ];

    await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros })
      .expect(200);

    const racha = await prisma.racha.findUnique({ where: { idAlumno } });
    expect(racha?.diasConsecutivos).toBe(3);
    expect(racha?.ultimaFechaPractica.toISOString()).toBe('2026-09-12T00:00:00.000Z');
  });

  it('RF-24: un lote que completa el 100% de un nivel otorga la insignia (mismo efecto que POST /practica)', async () => {
    await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros: [registroValido({ id: 'insignia-1', id_palabra: idPalabraCompleta })] })
      .expect(200);

    const insignia = await prisma.insignia.findUnique({
      where: { idAlumno_idNivel: { idAlumno, idNivel: idNivelFacil } },
    });
    expect(insignia).not.toBeNull();
  });

  it('400 si registros es un arreglo vacío — el cliente real nunca lo manda así', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros: [] })
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');
  });

  it('requiere sesión iniciada', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica/sync')
      .send({ registros: [registroValido()] })
      .expect(401);

    expect(respuesta.body.error.code).toBe('SESION_REQUERIDA');
  });

  it('400 si falta el id de cliente de un registro', async () => {
    const { id: _omitido, ...incompleto } = registroValido();

    const respuesta = await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros: [incompleto] })
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');
  });

  it('400 si registros no es un arreglo', async () => {
    const respuesta = await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({ registros: 'no-es-un-arreglo' })
      .expect(400);

    expect(respuesta.body.error.code).toBe('VALIDACION');
  });

  it('404 si algún id_palabra del lote no existe — el lote entero no se guarda (todo o nada)', async () => {
    await request(app.getHttpServer())
      .post('/practica/sync')
      .set('Authorization', `Bearer ${tokenAlumno}`)
      .send({
        registros: [
          registroValido({ id: 'valido' }),
          registroValido({ id: 'invalido', id_palabra: 999999999 }),
        ],
      })
      .expect(404);

    expect(await prisma.registroPractica.count({ where: { idAlumno } })).toBe(0);
  });
});

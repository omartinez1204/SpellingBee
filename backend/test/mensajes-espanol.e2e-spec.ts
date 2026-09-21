import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import bcrypt from 'bcrypt';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

// T-071 (RNF-01): el message de cada error llega tal cual a la pantalla de la
// app Flutter (ApiException.message → SnackBar/banner). Aquí se prueba, con el
// ValidationPipe, multer y el enrutador de Nest REALES, que ninguno llega en
// inglés — incluidos los que generan las librerías y no el código propio.

const PREFIJO_PRUEBA = 'TEST-T071-';
const PASSWORD = 'ClaveDePrueba123';
const USUARIO_PROFESOR = `${PREFIJO_PRUEBA}PROFESOR`;

// Palabras inglesas que no existen en español (se evitan "error", "total"...).
const INGLES = new Set([
  'must', 'should', 'shall', 'be', 'is', 'are', 'not', 'the', 'an', 'of', 'to',
  'and', 'or', 'unexpected', 'too', 'large', 'invalid', 'unauthorized',
  'forbidden', 'string', 'number', 'integer', 'array', 'empty', 'longer',
  'shorter', 'characters', 'property', 'exist', 'expected', 'field', 'file',
  'value', 'valid', 'required', 'missing', 'boolean', 'object', 'each',
  'nested', 'either', 'greater', 'less', 'than', 'cannot', 'get', 'input',
  'json', 'end', 'request', 'entity', 'payload', 'bad',
]);
const palabrasEnIngles = (texto: string) =>
  (texto.toLowerCase().match(/[\p{L}]+/gu) ?? []).filter((p) => INGLES.has(p));

describe('Mensajes de error en español (e2e) — RNF-01, T-071', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let tokenProfesor: string;
  let idPalabra: number;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    await prisma.usuario.create({
      data: {
        nombreUsuario: USUARIO_PROFESOR,
        contrasenaHash: await bcrypt.hash(PASSWORD, 12),
        rol: 'profesor',
        correoElectronico: 'profesor.t071@example.com',
        correoRecuperacion: 'profesor.t071@example.com',
        debeCambiarContrasena: false,
      },
    });
    const login = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ nombre_usuario: USUARIO_PROFESOR, contrasena: PASSWORD })
      .expect(200);
    tokenProfesor = login.body.access_token as string;

    const facil = await prisma.nivel.findFirstOrThrow({ where: { nombre: 'Fácil' } });
    const profesor = await prisma.usuario.findUniqueOrThrow({
      where: { nombreUsuario: USUARIO_PROFESOR },
    });
    const palabra = await prisma.palabra.create({
      data: {
        texto: `${PREFIJO_PRUEBA}palabra`,
        idNivel: facil.id,
        idProfesorAutor: profesor.id,
      },
    });
    idPalabra = palabra.id;
  });

  afterEach(async () => {
    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await prisma.usuario.deleteMany({
      where: { nombreUsuario: { startsWith: PREFIJO_PRUEBA } },
    });
    await app.close();
  });

  const conSesion = (r: request.Test) =>
    r.set('Authorization', `Bearer ${tokenProfesor}`);

  describe('mensajes que generan las librerías (no el código propio)', () => {
    it('propiedad desconocida en el body: "property foo should not exist" → español', async () => {
      const r = await conSesion(
        request(app.getHttpServer()).post('/admin/palabras'),
      )
        .send({ texto: `${PREFIJO_PRUEBA}x`, id_nivel: 1, foo: 1 })
        .expect(400);

      expect(r.body.error).toEqual({
        code: 'VALIDACION',
        message: 'La propiedad foo no está permitida.',
      });
    });

    it('propiedad desconocida en la query (?foo=1) → español', async () => {
      const r = await conSesion(
        request(app.getHttpServer()).get('/admin/palabras').query({ foo: 1 }),
      ).expect(400);

      expect(r.body.error.message).toBe('La propiedad foo no está permitida.');
    });

    it('audio de más de 5 MB (límite crudo de multer): el MISMO error de negocio que pasarse de 1 MB, no "File too large"', async () => {
      const r = await conSesion(
        request(app.getHttpServer()).post(`/admin/palabras/${idPalabra}/audio`),
      )
        .attach('audio', Buffer.alloc(6 * 1024 * 1024, 1), 'grande.mp3')
        .expect(400);

      expect(r.body.error).toEqual({
        code: 'AUDIO_TAMANO_INVALIDO',
        message: 'El archivo no puede pesar más de 1 MB.',
      });
    });

    it('audio de entre 1 MB y 5 MB sigue dando exactamente el mismo error (consistencia)', async () => {
      const r = await conSesion(
        request(app.getHttpServer()).post(`/admin/palabras/${idPalabra}/audio`),
      )
        .attach('audio', Buffer.alloc(2 * 1024 * 1024, 1), 'mediano.mp3')
        .expect(400);

      expect(r.body.error).toEqual({
        code: 'AUDIO_TAMANO_INVALIDO',
        message: 'El archivo no puede pesar más de 1 MB.',
      });
    });

    it('audio enviado en un campo del multipart con otro nombre: "Unexpected field" → español', async () => {
      const r = await conSesion(
        request(app.getHttpServer()).post(`/admin/palabras/${idPalabra}/audio`),
      )
        .attach('archivo', Buffer.alloc(1000, 1), 'x.mp3')
        .expect(400);

      expect(r.body.error).toEqual({
        code: 'CAMPO_ARCHIVO_INESPERADO',
        message: 'Campo de archivo inesperado: archivo.',
      });
    });

    it('ruta inexistente: "Cannot GET /..." → español', async () => {
      const r = await request(app.getHttpServer())
        .get('/nada-por-aqui')
        .expect(404);

      expect(r.body.error).toEqual({
        code: 'RUTA_NO_ENCONTRADA',
        message: 'La ruta solicitada no existe.',
      });
    });

    it('método no permitido en una ruta existente: "Cannot DELETE /niveles" → español', async () => {
      const r = await request(app.getHttpServer()).delete('/niveles').expect(404);

      expect(r.body.error.message).toBe('La ruta solicitada no existe.');
    });

    it('cuerpo JSON malformado ("Unexpected end of JSON input") → español', async () => {
      const r = await request(app.getHttpServer())
        .post('/auth/login')
        .set('Content-Type', 'application/json')
        .send('{"nombre_usuario": ')
        .expect(400);

      expect(r.body.error).toEqual({
        code: 'PETICION_INVALIDA',
        message: 'La petición no es válida.',
      });
    });

    it('sync con "registros" que no es un arreglo de objetos → todos los fragmentos en español', async () => {
      const r = await conSesion(
        request(app.getHttpServer()).post('/practica/sync'),
      )
        .send({ registros: 'x' })
        .expect(400);

      expect(r.body.error.message).toContain('Cada elemento de registros debe ser un objeto.');
      expect(palabrasEnIngles(r.body.error.message)).toEqual([]);
    });
  });

  describe('barrido: ningún mensaje de error tiene palabras en inglés', () => {
    it('recorre entradas inválidas de todos los endpoints con cuerpo o parámetros', async () => {
      const servidor = app.getHttpServer();
      // Cada petición se construye al usarla (una función): supertest abre el
      // servidor al crear cada una, y crearlas todas a la vez las hace chocar.
      const casos: Array<[string, () => request.Test]> = [
        ['registro {}', () => request(servidor).post('/auth/registro').send({})],
        ['registro extra', () => request(servidor).post('/auth/registro').send({ foo: 1 })],
        ['login {}', () => request(servidor).post('/auth/login').send({})],
        ['login mal', () => request(servidor).post('/auth/login').send({ nombre_usuario: 'nadie', contrasena: 'xxxxxxxx' })],
        ['recuperar {}', () => request(servidor).post('/auth/recuperar-password').send({})],
        ['restablecer {}', () => request(servidor).post('/auth/restablecer-password').send({})],
        ['cambiar sin sesión', () => request(servidor).patch('/auth/cambiar-password').send({})],
        ['cambiar {}', () => conSesion(request(servidor).patch('/auth/cambiar-password')).send({})],
        ['admin sin sesión', () => request(servidor).get('/admin/palabras')],
        ['admin token inválido', () => request(servidor).get('/admin/palabras').set('Authorization', 'Bearer no.es.jwt')],
        ['admin ?limite=51', () => conSesion(request(servidor).get('/admin/palabras').query({ limite: 51 }))],
        ['admin ?pagina=abc', () => conSesion(request(servidor).get('/admin/palabras').query({ pagina: 'abc' }))],
        ['crear {}', () => conSesion(request(servidor).post('/admin/palabras')).send({})],
        ['crear tipos', () => conSesion(request(servidor).post('/admin/palabras')).send({ texto: 1, id_nivel: 'x' })],
        ['editar tipos', () => conSesion(request(servidor).patch(`/admin/palabras/${idPalabra}`)).send({ texto: 5, id_nivel: 'x' })],
        ['editar id malo', () => conSesion(request(servidor).patch('/admin/palabras/abc')).send({ texto: 'x' })],
        ['ocultar {}', () => conSesion(request(servidor).patch(`/admin/palabras/${idPalabra}/ocultar`)).send({})],
        ['audio sin archivo', () => conSesion(request(servidor).post(`/admin/palabras/${idPalabra}/audio`))],
        ['audio .txt', () => conSesion(request(servidor).post(`/admin/palabras/${idPalabra}/audio`)).attach('audio', Buffer.alloc(100, 1), 'x.txt')],
        ['niveles/abc/palabras', () => request(servidor).get('/niveles/abc/palabras')],
        ['niveles/99999/palabras', () => request(servidor).get('/niveles/99999/palabras')],
        ['palabras/abc', () => request(servidor).get('/palabras/abc')],
        ['mejor-tiempo sin sesión', () => request(servidor).get('/practica/mejor-tiempo/1')],
        ['practica {}', () => conSesion(request(servidor).post('/practica')).send({})],
        ['practica fecha mala', () => conSesion(request(servidor).post('/practica')).send({ id_palabra: idPalabra, tiempo_segundos: 5, oracion_alumno: 'x', deletreo_correcto: true, fecha_local: 'hoy' })],
        ['sync {}', () => conSesion(request(servidor).post('/practica/sync')).send({})],
        ['sync registro vacío', () => conSesion(request(servidor).post('/practica/sync')).send({ registros: [{}] })],
        ['racha sin fecha', () => conSesion(request(servidor).get('/racha'))],
        ['insignias sin sesión', () => request(servidor).get('/progreso/insignias')],
        ['alumnos ?nivel=abc', () => conSesion(request(servidor).get('/admin/alumnos').query({ nivel: 'abc' }))],
        ['alumnos ?carrera=Medicina', () => conSesion(request(servidor).get('/admin/alumnos').query({ carrera: 'Medicina' }))],
        ['alumnos/abc', () => conSesion(request(servidor).get('/admin/alumnos/abc'))],
        ['ruta inexistente', () => request(servidor).get('/nada')],
        ['JSON malformado', () => request(servidor).post('/auth/login').set('Content-Type', 'application/json').send('{"x": ')],
      ];

      const ofensas: string[] = [];
      let revisados = 0;
      for (const [nombre, hacerPeticion] of casos) {
        const r = await hacerPeticion();
        expect(r.status, `${nombre}: debería ser un error`).toBeGreaterThanOrEqual(400);
        const mensaje = String(r.body?.error?.message ?? '');
        expect(mensaje, `${nombre}: sin mensaje`).not.toBe('');
        revisados++;
        for (const fragmento of mensaje.split('; ')) {
          const ingles = palabrasEnIngles(fragmento);
          if (ingles.length > 0) ofensas.push(`${nombre}: «${fragmento}» [${ingles.join(', ')}]`);
        }
      }

      expect(revisados).toBe(casos.length);
      expect(ofensas).toEqual([]);
    });
  });
});

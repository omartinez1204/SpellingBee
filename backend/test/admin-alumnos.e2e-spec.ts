import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import bcrypt from 'bcrypt';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const PREFIJO_PRUEBA = 'TEST-T050-';
const PASSWORD = 'ClaveDePrueba123';

const USUARIO_PROFESOR = `${PREFIJO_PRUEBA}PROFESOR`;
const USUARIO_ALUMNO_A = `${PREFIJO_PRUEBA}ALUMNO-A`;
const USUARIO_ALUMNO_B = `${PREFIJO_PRUEBA}ALUMNO-B`;

describe('AdminAlumnosController (e2e) - GET /admin/alumnos', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let idFacil: number;
  let idIntermedio: number;
  let idDificil: number;
  let idProfesor: number;
  let tokenProfesor: string;
  let tokenAlumno: string;

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
    const dificil = await prisma.nivel.findFirst({ where: { nombre: 'Difícil' } });
    if (!facil || !intermedio || !dificil) {
      throw new Error('Faltan niveles del seed — corre el seed antes de las pruebas.');
    }
    idFacil = facil.id;
    idIntermedio = intermedio.id;
    idDificil = dificil.id;

    const profesor = await prisma.usuario.create({
      data: {
        nombreUsuario: USUARIO_PROFESOR,
        contrasenaHash: await bcrypt.hash(PASSWORD, 12),
        rol: 'profesor',
        correoElectronico: 'profesor.t050@example.com',
        correoRecuperacion: 'profesor.t050@example.com',
        debeCambiarContrasena: false,
      },
    });
    idProfesor = profesor.id;

    async function login(nombre_usuario: string) {
      const res = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ nombre_usuario, contrasena: PASSWORD })
        .expect(200);
      return res.body.access_token as string;
    }
    tokenProfesor = await login(USUARIO_PROFESOR);

    async function registrarAlumno(matricula: string, apellidoMaterno: string) {
      await request(app.getHttpServer())
        .post('/auth/registro')
        .send({
          matricula,
          nombre: 'Alumno',
          apellido_paterno: 'De Prueba',
          apellido_materno: apellidoMaterno,
          carrera: 'Ingeniería en Desarrollo de Software',
          semestre: 5,
          correo: `${matricula.toLowerCase()}@example.com`,
          contrasena: PASSWORD,
          acepto_aviso_privacidad: true,
        })
        .expect(201);
      return login(matricula);
    }
    tokenAlumno = await registrarAlumno(USUARIO_ALUMNO_A, 'T050-A');
    await registrarAlumno(USUARIO_ALUMNO_B, 'T050-B');
  });

  afterEach(async () => {
    await prisma.registroPractica.deleteMany({
      where: { palabra: { texto: { startsWith: PREFIJO_PRUEBA } } },
    });
    await prisma.palabra.deleteMany({
      where: { texto: { startsWith: PREFIJO_PRUEBA } },
    });
    await prisma.perfilAlumno.deleteMany({
      where: { usuario: { nombreUsuario: { startsWith: PREFIJO_PRUEBA } } },
    });
    await prisma.usuario.deleteMany({
      where: { nombreUsuario: { startsWith: PREFIJO_PRUEBA } },
    });
    await app.close();
  });

  async function alumnoId(matricula: string): Promise<number> {
    const usuario = await prisma.usuario.findUniqueOrThrow({
      where: { nombreUsuario: matricula },
    });
    return usuario.id;
  }

  async function crearPalabra(texto: string, idNivel: number) {
    return prisma.palabra.create({
      data: { texto: `${PREFIJO_PRUEBA}${texto}`, idNivel, idProfesorAutor: idProfesor },
    });
  }

  async function practicar(idAlumno: number, idPalabra: number, idNivelEnPractica: number) {
    return prisma.registroPractica.create({
      data: {
        idAlumno,
        idPalabra,
        idNivelEnPractica,
        tiempoSegundos: 10,
        oracionAlumno: 'x',
        deletreoCorrecto: true,
        sincronizado: true,
      },
    });
  }

  describe('autorización (RNF-07)', () => {
    it('sin sesión → 401', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .expect(401);
      expect(res.body.error.code).toBe('SESION_REQUERIDA');
    });

    it('con alumno → 403', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .expect(403);
      expect(res.body.error.code).toBe('ADMIN_SOLO_PROFESOR');
    });

    it('con profesor → 200', async () => {
      await request(app.getHttpServer())
        .get('/admin/alumnos')
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);
    });
  });

  describe('RF-28: lista y avance general', () => {
    it('un alumno sin ninguna práctica aparece con 0 en los 3 niveles, no se omite', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ limite: 50 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);

      const idB = await alumnoId(USUARIO_ALUMNO_B);
      const filaB = respuesta.body.alumnos.find((a: { id: number }) => a.id === idB);
      expect(filaB).toBeDefined();
      expect(filaB.matricula).toBe(USUARIO_ALUMNO_B);
      expect(filaB.nombre).toBe('Alumno');
      expect(filaB.apellido_paterno).toBe('De Prueba');
      expect(filaB.apellido_materno).toBe('T050-B');
      expect(filaB.carrera).toBe('Ingeniería en Desarrollo de Software');
      expect(filaB.semestre).toBe(5);
      expect(filaB.avance).toHaveLength(3);
      expect(filaB.avance).toEqual(
        expect.arrayContaining([
          { id_nivel: idFacil, palabras_practicadas: 0 },
          { id_nivel: idIntermedio, palabras_practicadas: 0 },
          { id_nivel: idDificil, palabras_practicadas: 0 },
        ]),
      );
    });

    it('cuenta cuántas palabras DISTINTAS de cada nivel practicó, no el total de intentos', async () => {
      const idA = await alumnoId(USUARIO_ALUMNO_A);
      const p1 = await crearPalabra('facil-1', idFacil);
      const p2 = await crearPalabra('facil-2', idFacil);
      const p3 = await crearPalabra('intermedio-1', idIntermedio);

      // Practica p1 dos veces (mismo intento repetido) y p2 una vez, ambas
      // en Fácil: deben contar como 2 palabras distintas, no 3 intentos.
      await practicar(idA, p1.id, idFacil);
      await practicar(idA, p1.id, idFacil);
      await practicar(idA, p2.id, idFacil);
      await practicar(idA, p3.id, idIntermedio);

      const respuesta = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ limite: 50 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);

      const filaA = respuesta.body.alumnos.find((a: { id: number }) => a.id === idA);
      expect(filaA.avance).toEqual(
        expect.arrayContaining([
          { id_nivel: idFacil, palabras_practicadas: 2 },
          { id_nivel: idIntermedio, palabras_practicadas: 1 },
          { id_nivel: idDificil, palabras_practicadas: 0 },
        ]),
      );
    });

    it('RF-09: usa el nivel EN EL MOMENTO de practicar (snapshot), no el nivel actual de la palabra', async () => {
      const idA = await alumnoId(USUARIO_ALUMNO_A);
      const palabra = await crearPalabra('nivel-cambia', idFacil);
      await practicar(idA, palabra.id, idFacil);

      // El profesor mueve la palabra a otro nivel DESPUÉS de que se practicó.
      await prisma.palabra.update({
        where: { id: palabra.id },
        data: { idNivel: idDificil },
      });

      const respuesta = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ limite: 50 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);

      const filaA = respuesta.body.alumnos.find((a: { id: number }) => a.id === idA);
      const avanceFacil = filaA.avance.find(
        (n: { id_nivel: number }) => n.id_nivel === idFacil,
      );
      const avanceDificil = filaA.avance.find(
        (n: { id_nivel: number }) => n.id_nivel === idDificil,
      );
      // Sigue contando en Fácil (donde se practicó), no en Difícil (donde
      // quedó la palabra después del cambio).
      expect(avanceFacil.palabras_practicadas).toBe(1);
      expect(avanceDificil.palabras_practicadas).toBe(0);
    });
  });

  describe('paginación (RNF-12)', () => {
    it('pagina correctamente y regresa metadatos de paginación', async () => {
      const pagina1 = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ pagina: 1, limite: 1 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);
      expect(pagina1.body.alumnos).toHaveLength(1);
      expect(pagina1.body.pagina).toBe(1);
      expect(pagina1.body.limite).toBe(1);
      expect(pagina1.body.total).toBeGreaterThanOrEqual(2);

      const pagina2 = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ pagina: 2, limite: 1 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);
      expect(pagina2.body.alumnos).toHaveLength(1);
      expect(pagina2.body.alumnos[0].id).not.toBe(pagina1.body.alumnos[0].id);
    });

    it('sin query params, usa una página por defecto (no trae todo de una vez)', async () => {
      const respuesta = await request(app.getHttpServer())
        .get('/admin/alumnos')
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);

      expect(respuesta.body.pagina).toBe(1);
      expect(respuesta.body.alumnos.length).toBeLessThanOrEqual(respuesta.body.limite);
    });

    it('400 si limite excede el tope de RNF-12 (50)', async () => {
      await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ limite: 51 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(400);
    });

    it('400 si pagina o limite no son válidos', async () => {
      await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ pagina: 0 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(400);

      await request(app.getHttpServer())
        .get('/admin/alumnos')
        .query({ limite: 'abc' })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(400);
    });
  });
});

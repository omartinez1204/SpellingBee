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

  // Para las pruebas de filtro (RF-30) hace falta variar carrera/semestre,
  // a diferencia de ALUMNO_A/B del beforeEach (ambos con los mismos valores).
  async function registrarAlumnoPersonalizado(
    matricula: string,
    carrera: string,
    semestre: number,
  ): Promise<number> {
    await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula,
        nombre: 'Alumno',
        apellido_paterno: 'De Prueba',
        apellido_materno: 'Filtro',
        carrera,
        semestre,
        correo: `${matricula.toLowerCase()}@example.com`,
        contrasena: PASSWORD,
        acepto_aviso_privacidad: true,
      })
      .expect(201);
    return alumnoId(matricula);
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

  describe('GET /admin/alumnos/:id (RF-29): detalle por intento', () => {
    describe('autorización (RNF-07)', () => {
      it('sin sesión → 401', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);
        const res = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .expect(401);
        expect(res.body.error.code).toBe('SESION_REQUERIDA');
      });

      it('con alumno → 403 (incluso consultando su propio id)', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);
        const res = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .set('Authorization', `Bearer ${tokenAlumno}`)
          .expect(403);
        expect(res.body.error.code).toBe('ADMIN_SOLO_PROFESOR');
      });
    });

    it('devuelve palabra, tiempo y oración de CADA intento, incluidos los repetidos de la misma palabra', async () => {
      const idA = await alumnoId(USUARIO_ALUMNO_A);
      const palabra = await crearPalabra('detalle-repetida', idFacil);
      await prisma.registroPractica.create({
        data: {
          idAlumno: idA,
          idPalabra: palabra.id,
          idNivelEnPractica: idFacil,
          tiempoSegundos: 20,
          oracionAlumno: 'First attempt sentence.',
          deletreoCorrecto: false,
          sincronizado: true,
        },
      });
      await prisma.registroPractica.create({
        data: {
          idAlumno: idA,
          idPalabra: palabra.id,
          idNivelEnPractica: idFacil,
          tiempoSegundos: 12,
          oracionAlumno: 'Second attempt sentence, faster.',
          deletreoCorrecto: true,
          sincronizado: true,
        },
      });

      const respuesta = await request(app.getHttpServer())
        .get(`/admin/alumnos/${idA}`)
        .query({ limite: 50 })
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);

      // A diferencia de RF-28, aquí SÍ hay 2 filas para la misma palabra —
      // uno por cada intento real, sin deduplicar.
      expect(respuesta.body.intentos).toHaveLength(2);
      expect(respuesta.body.total).toBe(2);
      expect(respuesta.body.intentos).toEqual(
        expect.arrayContaining([
          {
            id_palabra: palabra.id,
            palabra: `${PREFIJO_PRUEBA}detalle-repetida`,
            tiempo_segundos: 20,
            oracion_alumno: 'First attempt sentence.',
          },
          {
            id_palabra: palabra.id,
            palabra: `${PREFIJO_PRUEBA}detalle-repetida`,
            tiempo_segundos: 12,
            oracion_alumno: 'Second attempt sentence, faster.',
          },
        ]),
      );
      // RF-29 enumera solo palabra/tiempo/oración — deletreo_correcto no es
      // parte de esta tabla, a propósito.
      expect(respuesta.body.intentos[0].deletreo_correcto).toBeUndefined();
    });

    it('un alumno sin ningún intento regresa 200 con lista vacía (no es un error)', async () => {
      const idB = await alumnoId(USUARIO_ALUMNO_B);
      const respuesta = await request(app.getHttpServer())
        .get(`/admin/alumnos/${idB}`)
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);

      expect(respuesta.body.intentos).toEqual([]);
      expect(respuesta.body.total).toBe(0);
    });

    it('404 si el id no corresponde a ningún alumno', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/alumnos/999999')
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(404);
      expect(res.body.error.code).toBe('ALUMNO_NO_ENCONTRADO');
    });

    it('404 si el id es de un profesor, no de un alumno', async () => {
      const res = await request(app.getHttpServer())
        .get(`/admin/alumnos/${idProfesor}`)
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(404);
      expect(res.body.error.code).toBe('ALUMNO_NO_ENCONTRADO');
    });

    it('400 si el id no es numérico', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/alumnos/abc')
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(400);
      expect(res.body.error.code).toBe('ALUMNO_ID_INVALIDO');
    });

    describe('paginación (RNF-12)', () => {
      it('pagina correctamente y regresa metadatos de paginación', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);
        const palabra = await crearPalabra('detalle-paginacion', idFacil);
        for (let i = 0; i < 3; i++) {
          await practicar(idA, palabra.id, idFacil);
        }

        const pagina1 = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ pagina: 1, limite: 2 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);
        expect(pagina1.body.intentos).toHaveLength(2);
        expect(pagina1.body.total).toBe(3);
        expect(pagina1.body.total_paginas).toBe(2);

        const pagina2 = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ pagina: 2, limite: 2 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);
        expect(pagina2.body.intentos).toHaveLength(1);
      });

      it('400 si limite excede el tope de RNF-12 (50)', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);
        await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ limite: 51 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(400);
      });
    });
  });

  describe('RF-30 (T-052): filtros combinables de nivel, carrera y semestre', () => {
    describe('GET /admin/alumnos', () => {
      it('filtra por carrera sola', async () => {
        const idAgro = await registrarAlumnoPersonalizado(
          `${PREFIJO_PRUEBA}AGRO`,
          'Ingeniería en Agroalimentos',
          3,
        );
        const idMiPymes = await registrarAlumnoPersonalizado(
          `${PREFIJO_PRUEBA}MIPYMES`,
          'Licenciatura en MiPymes',
          3,
        );

        const respuesta = await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({ limite: 50, carrera: 'Ingeniería en Agroalimentos' })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        const ids = respuesta.body.alumnos.map((a: { id: number }) => a.id);
        expect(ids).toContain(idAgro);
        expect(ids).not.toContain(idMiPymes);
      });

      it('filtra por semestre solo', async () => {
        const idSemestre2 = await registrarAlumnoPersonalizado(
          `${PREFIJO_PRUEBA}SEM2`,
          'Ingeniería en Desarrollo de Software',
          2,
        );
        const idSemestre8 = await registrarAlumnoPersonalizado(
          `${PREFIJO_PRUEBA}SEM8`,
          'Ingeniería en Desarrollo de Software',
          8,
        );

        const respuesta = await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({ limite: 50, semestre: 2 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        const ids = respuesta.body.alumnos.map((a: { id: number }) => a.id);
        expect(ids).toContain(idSemestre2);
        expect(ids).not.toContain(idSemestre8);
      });

      it('filtra por nivel: angosta el arreglo de avance a solo ese nivel, sin excluir alumnos', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);

        const respuesta = await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({ limite: 50, nivel: idIntermedio })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        const filaA = respuesta.body.alumnos.find((a: { id: number }) => a.id === idA);
        // Sigue apareciendo (nunca practicó nada) pero el avance trae SOLO
        // Intermedio, no los 3 niveles.
        expect(filaA).toBeDefined();
        expect(filaA.avance).toEqual([
          { id_nivel: idIntermedio, palabras_practicadas: 0 },
        ]);
      });

      it('combina los 3 filtros simultáneamente (AND, no OR)', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A); // ISD, semestre 5
        const idOtraCarrera = await registrarAlumnoPersonalizado(
          `${PREFIJO_PRUEBA}COMBINADO-CARRERA`,
          'Licenciatura en MiPymes',
          5,
        );
        const idOtroSemestre = await registrarAlumnoPersonalizado(
          `${PREFIJO_PRUEBA}COMBINADO-SEMESTRE`,
          'Ingeniería en Desarrollo de Software',
          1,
        );

        const respuesta = await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({
            limite: 50,
            carrera: 'Ingeniería en Desarrollo de Software',
            semestre: 5,
          })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        const ids = respuesta.body.alumnos.map((a: { id: number }) => a.id);
        expect(ids).toContain(idA);
        expect(ids).not.toContain(idOtraCarrera);
        expect(ids).not.toContain(idOtroSemestre);
      });

      it('400 si carrera no es una de las 3 válidas', async () => {
        await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({ carrera: 'Medicina' })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(400);
      });

      it('400 si semestre está fuera de 1-10', async () => {
        await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({ semestre: 11 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(400);
      });

      it('400 si nivel no es un entero positivo', async () => {
        await request(app.getHttpServer())
          .get('/admin/alumnos')
          .query({ nivel: 0 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(400);
      });
    });

    describe('GET /admin/alumnos/:id', () => {
      it('filtra los intentos por nivel', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);
        const palabraFacil = await crearPalabra('filtro-facil', idFacil);
        const palabraDificil = await crearPalabra('filtro-dificil', idDificil);
        await practicar(idA, palabraFacil.id, idFacil);
        await practicar(idA, palabraDificil.id, idDificil);

        const respuesta = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ nivel: idFacil })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        expect(respuesta.body.total).toBe(1);
        expect(respuesta.body.intentos).toHaveLength(1);
        expect(respuesta.body.intentos[0].id_palabra).toBe(palabraFacil.id);
      });

      it('carrera/semestre que SÍ coinciden con el alumno: resultado normal', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A); // ISD, semestre 5 (ver beforeEach)
        const palabra = await crearPalabra('filtro-coincide', idFacil);
        await practicar(idA, palabra.id, idFacil);

        const respuesta = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({
            carrera: 'Ingeniería en Desarrollo de Software',
            semestre: 5,
          })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        expect(respuesta.body.total).toBe(1);
      });

      it('carrera que NO coincide con el alumno: 200 con lista vacía, no 404', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A); // ISD, no MiPymes
        const palabra = await crearPalabra('filtro-no-coincide-carrera', idFacil);
        await practicar(idA, palabra.id, idFacil);

        const respuesta = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ carrera: 'Licenciatura en MiPymes' })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        expect(respuesta.body.total).toBe(0);
        expect(respuesta.body.intentos).toEqual([]);
      });

      it('semestre que NO coincide con el alumno: 200 con lista vacía, no 404', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A); // semestre 5
        const palabra = await crearPalabra('filtro-no-coincide-semestre', idFacil);
        await practicar(idA, palabra.id, idFacil);

        const respuesta = await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ semestre: 9 })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(200);

        expect(respuesta.body.total).toBe(0);
      });

      it('400 si carrera no es una de las 3 válidas', async () => {
        const idA = await alumnoId(USUARIO_ALUMNO_A);
        await request(app.getHttpServer())
          .get(`/admin/alumnos/${idA}`)
          .query({ carrera: 'Medicina' })
          .set('Authorization', `Bearer ${tokenProfesor}`)
          .expect(400);
      });
    });
  });
});

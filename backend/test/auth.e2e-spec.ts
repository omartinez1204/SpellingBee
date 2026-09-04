import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Test, TestingModule } from '@nestjs/testing';
import bcrypt from 'bcrypt';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

const MATRICULA_OK = 'TEST-T010-0001';
const MATRICULA_DUP = 'TEST-T010-0002';
const MATRICULAS_DE_PRUEBA = [MATRICULA_OK, MATRICULA_DUP];

function cuerpoValido(overrides: Record<string, unknown> = {}) {
  return {
    matricula: MATRICULA_OK,
    nombre: 'Ana',
    apellido_paterno: 'García',
    apellido_materno: 'López',
    carrera: 'Ingeniería en Desarrollo de Software',
    semestre: 3,
    correo: 'ana.garcia@example.com',
    contrasena: 'ClaveSegura123',
    acepto_aviso_privacidad: true,
    ...overrides,
  };
}

describe('AuthController (e2e) - POST /auth/registro', () => {
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
    // Limpieza: estos tests escriben en la misma dev.db que usa el resto del
    // proyecto, así que no deben dejar cuentas de prueba atrás.
    await prisma.perfilAlumno.deleteMany({
      where: { usuario: { nombreUsuario: { in: MATRICULAS_DE_PRUEBA } } },
    });
    await prisma.usuario.deleteMany({
      where: { nombreUsuario: { in: MATRICULAS_DE_PRUEBA } },
    });
    await app.close();
  });

  it('crea la cuenta con los 8 campos y el aviso de privacidad aceptado', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/registro')
      .send(cuerpoValido())
      .expect(201);

    expect(res.body).toMatchObject({
      nombreUsuario: MATRICULA_OK,
      rol: 'alumno',
    });
    expect(res.body.contrasenaHash).toBeUndefined();
    expect(res.body.contrasena).toBeUndefined();

    const enBd = await prisma.usuario.findUnique({
      where: { nombreUsuario: MATRICULA_OK },
      include: { perfilAlumno: true },
    });
    expect(enBd?.debeCambiarContrasena).toBe(false);
    expect(enBd?.contrasenaHash).not.toBe('ClaveSegura123');
    expect(enBd?.perfilAlumno?.carrera).toBe(
      'Ingeniería en Desarrollo de Software',
    );
    expect(enBd?.perfilAlumno?.semestre).toBe(3);
  });

  it('rechaza el registro si falta un campo obligatorio (nombre)', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: MATRICULA_DUP,
        // nombre omitido a propósito
        apellido_paterno: 'García',
        apellido_materno: 'López',
        carrera: 'Ingeniería en Desarrollo de Software',
        semestre: 3,
        correo: 'ana.garcia@example.com',
        contrasena: 'ClaveSegura123',
        acepto_aviso_privacidad: true,
      })
      .expect(400);

    expect(res.body.error.code).toBe('VALIDACION');

    const enBd = await prisma.usuario.findUnique({
      where: { nombreUsuario: MATRICULA_DUP },
    });
    expect(enBd).toBeNull();
  });

  it('rechaza el registro si no se acepta el aviso de privacidad', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/registro')
      .send(
        cuerpoValido({
          matricula: MATRICULA_DUP,
          acepto_aviso_privacidad: false,
        }),
      )
      .expect(400);

    expect(res.body.error.code).toBe('VALIDACION');
  });

  it('rechaza la forma abreviada de carrera (solo valen los 3 nombres literales del ERS)', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/registro')
      .send(
        cuerpoValido({
          matricula: MATRICULA_DUP,
          carrera: 'Desarrollo de Software',
        }),
      )
      .expect(400);

    expect(res.body.error.code).toBe('VALIDACION');
  });

  it('rechaza una matrícula duplicada', async () => {
    await request(app.getHttpServer())
      .post('/auth/registro')
      .send(cuerpoValido())
      .expect(201);

    const res = await request(app.getHttpServer())
      .post('/auth/registro')
      .send(cuerpoValido())
      .expect(409);

    expect(res.body.error.code).toBe('MATRICULA_DUPLICADA');

    const cuentas = await prisma.usuario.count({
      where: { nombreUsuario: MATRICULA_OK },
    });
    expect(cuentas).toBe(1);
  });

  it('rechaza campos no reconocidos en el body (ej. intentar fijar rol)', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/registro')
      .send(cuerpoValido({ matricula: MATRICULA_DUP, rol: 'profesor' }))
      .expect(400);

    expect(res.body.error.code).toBe('VALIDACION');
  });
});

describe('AuthController (e2e) - POST /auth/login', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;
  let jwtService: JwtService;

  const USUARIO_ALUMNO = 'TEST-T011-ALUMNO';
  const USUARIO_PROFESOR = 'TEST-T011-PROFESOR';
  const CONTRASENA_ALUMNO = 'ClaveAlumno123';
  const CONTRASENA_PROFESOR = 'ClaveProfesor123';

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    jwtService = app.get(JwtService);

    // Alumno vía el propio endpoint de registro (RF-01).
    await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: USUARIO_ALUMNO,
        nombre: 'Bruno',
        apellido_paterno: 'Ramírez',
        apellido_materno: 'Solís',
        carrera: 'Ingeniería en Agroalimentos',
        semestre: 4,
        correo: 'bruno@example.com',
        contrasena: CONTRASENA_ALUMNO,
        acepto_aviso_privacidad: true,
      })
      .expect(201);

    // Profesor: no hay endpoint de alta (RF-02 dice que solo el equipo de
    // desarrollo los crea, como en el seed de T-002) — se inserta directo.
    await prisma.usuario.create({
      data: {
        nombreUsuario: USUARIO_PROFESOR,
        contrasenaHash: await bcrypt.hash(CONTRASENA_PROFESOR, 12),
        rol: 'profesor',
        correoElectronico: 'profesor.test@example.com',
        correoRecuperacion: 'profesor.test@example.com',
        debeCambiarContrasena: true,
      },
    });
  });

  afterEach(async () => {
    await prisma.perfilAlumno.deleteMany({
      where: { usuario: { nombreUsuario: USUARIO_ALUMNO } },
    });
    await prisma.usuario.deleteMany({
      where: { nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_PROFESOR] } },
    });
    await app.close();
  });

  it('permite login de alumno con matrícula', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ nombre_usuario: USUARIO_ALUMNO, contrasena: CONTRASENA_ALUMNO })
      .expect(200);

    expect(res.body).toMatchObject({
      rol: 'alumno',
      debe_cambiar_contrasena: false,
    });
    expect(typeof res.body.access_token).toBe('string');
  });

  it('permite login de profesor con el mismo endpoint, usando su username', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({
        nombre_usuario: USUARIO_PROFESOR,
        contrasena: CONTRASENA_PROFESOR,
      })
      .expect(200);

    expect(res.body).toMatchObject({
      rol: 'profesor',
      debe_cambiar_contrasena: true,
    });
  });

  it('el JWT trae sub, rol y debe_cambiar_contrasena en el payload', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({
        nombre_usuario: USUARIO_PROFESOR,
        contrasena: CONTRASENA_PROFESOR,
      })
      .expect(200);

    const usuario = await prisma.usuario.findUniqueOrThrow({
      where: { nombreUsuario: USUARIO_PROFESOR },
    });
    const payload = jwtService.verify(res.body.access_token);

    expect(payload).toMatchObject({
      sub: usuario.id,
      rol: 'profesor',
      debe_cambiar_contrasena: true,
    });
  });

  it('la respuesta no incluye el hash de la contraseña ni otros campos sensibles', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ nombre_usuario: USUARIO_ALUMNO, contrasena: CONTRASENA_ALUMNO })
      .expect(200);

    expect(Object.keys(res.body).sort()).toEqual(
      ['access_token', 'debe_cambiar_contrasena', 'rol'].sort(),
    );
    expect(JSON.stringify(res.body)).not.toContain(CONTRASENA_ALUMNO);
  });

  it('contraseña incorrecta: mensaje genérico, no "usuario no existe" vs "contraseña incorrecta"', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({
        nombre_usuario: USUARIO_ALUMNO,
        contrasena: 'la-clave-equivocada',
      })
      .expect(401);

    expect(res.body.error).toEqual({
      code: 'CREDENCIALES_INVALIDAS',
      message: 'Usuario o contraseña incorrectos.',
    });
  });

  it('usuario inexistente: exactamente el mismo error que contraseña incorrecta', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({
        nombre_usuario: 'NO-EXISTE-ESTE-USUARIO',
        contrasena: 'lo-que-sea',
      })
      .expect(401);

    expect(res.body.error).toEqual({
      code: 'CREDENCIALES_INVALIDAS',
      message: 'Usuario o contraseña incorrectos.',
    });
  });
});

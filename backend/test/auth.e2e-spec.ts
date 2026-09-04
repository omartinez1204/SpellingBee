import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Test, TestingModule } from '@nestjs/testing';
import bcrypt from 'bcrypt';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

async function leerUltimaEntradaDelLog(
  nombreUsuario: string,
): Promise<{ token: string; destinatario: string; enlace: string }> {
  const contenido = await readFile('dev-emails.log', 'utf8').catch(() => '');
  const lineas = contenido.trim().split('\n').filter(Boolean);
  for (let i = lineas.length - 1; i >= 0; i--) {
    const entrada = JSON.parse(lineas[i]);
    if (entrada.nombreUsuario === nombreUsuario) return entrada;
  }
  throw new Error(
    `No se encontró un correo para "${nombreUsuario}" en dev-emails.log`,
  );
}

async function leerUltimoTokenDelLog(nombreUsuario: string): Promise<string> {
  return (await leerUltimaEntradaDelLog(nombreUsuario)).token;
}

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

describe('AuthController (e2e) - POST /auth/logout', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('responde 200 sin requerir sesión (stateless, RF-04)', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/logout')
      .expect(200);

    expect(typeof res.body.mensaje).toBe('string');
  });

  it('ignora cualquier body que le manden (no hay nada que procesar)', async () => {
    await request(app.getHttpServer())
      .post('/auth/logout')
      .send({ lo_que_sea: 'no debería importar' })
      .expect(200);
  });
});

describe('AuthController (e2e) - recuperar-password / restablecer-password', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;

  const USUARIO = 'TEST-T013-ALUMNO';
  const PASSWORD_ORIGINAL = 'ClaveOriginal123';

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: USUARIO,
        nombre: 'Diana',
        apellido_paterno: 'Torres',
        apellido_materno: 'Vega',
        carrera: 'Ingeniería en Agroalimentos',
        semestre: 6,
        correo: 'diana@example.com',
        contrasena: PASSWORD_ORIGINAL,
        acepto_aviso_privacidad: true,
      })
      .expect(201);
  });

  afterEach(async () => {
    await prisma.perfilAlumno.deleteMany({
      where: { usuario: { nombreUsuario: USUARIO } },
    });
    await prisma.usuario.deleteMany({ where: { nombreUsuario: USUARIO } });
    await app.close();
  });

  it('genera un token (guardado como hash), lo "envía" por el mail service de dev, y permite restablecer una sola vez', async () => {
    const resSolicitud = await request(app.getHttpServer())
      .post('/auth/recuperar-password')
      .send({ nombre_usuario: USUARIO })
      .expect(200);
    expect(typeof resSolicitud.body.mensaje).toBe('string');

    const usuarioTrasSolicitud = await prisma.usuario.findUniqueOrThrow({
      where: { nombreUsuario: USUARIO },
    });
    expect(usuarioTrasSolicitud.tokenRestablecimiento).not.toBeNull();
    expect(usuarioTrasSolicitud.tokenRestablecimientoExpira).not.toBeNull();

    const correo = await leerUltimaEntradaDelLog(USUARIO);
    const token = correo.token;
    // en la BD debe estar el hash del token, nunca el token en claro
    expect(usuarioTrasSolicitud.tokenRestablecimiento).toBe(
      createHash('sha256').update(token).digest('hex'),
    );
    expect(usuarioTrasSolicitud.tokenRestablecimiento).not.toBe(token);
    // el alumno no tiene correoRecuperacion aparte (RF-01): el destino es su
    // propio correo de registro.
    expect(correo.destinatario).toBe('diana@example.com');

    const nuevaPassword = 'ClaveNueva456';
    await request(app.getHttpServer())
      .post('/auth/restablecer-password')
      .send({ token, contrasena_nueva: nuevaPassword })
      .expect(200);

    // la contraseña nueva funciona, la vieja ya no
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ nombre_usuario: USUARIO, contrasena: nuevaPassword })
      .expect(200);
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ nombre_usuario: USUARIO, contrasena: PASSWORD_ORIGINAL })
      .expect(401);

    // el mismo token no sirve una segunda vez (un solo uso)
    const resReuso = await request(app.getHttpServer())
      .post('/auth/restablecer-password')
      .send({ token, contrasena_nueva: 'OtraClaveMas789' })
      .expect(400);
    expect(resReuso.body.error.code).toBe('TOKEN_RESTABLECIMIENTO_INVALIDO');
  });

  it('la expiración del token es corta (15-30 min), no horas', async () => {
    const antesDeSolicitar = Date.now();
    await request(app.getHttpServer())
      .post('/auth/recuperar-password')
      .send({ nombre_usuario: USUARIO })
      .expect(200);

    const usuario = await prisma.usuario.findUniqueOrThrow({
      where: { nombreUsuario: USUARIO },
    });
    const minutos =
      (usuario.tokenRestablecimientoExpira!.getTime() - antesDeSolicitar) /
      60_000;

    expect(minutos).toBeGreaterThanOrEqual(15);
    // +0.5 min de margen por la latencia real entre "antesDeSolicitar" y el
    // Date.now() que corre dentro del servicio al procesar la petición.
    expect(minutos).toBeLessThanOrEqual(30.5);
  });

  it('responde igual exista o no la cuenta (no debe servir para enumerar usuarios)', async () => {
    const resExiste = await request(app.getHttpServer())
      .post('/auth/recuperar-password')
      .send({ nombre_usuario: USUARIO })
      .expect(200);

    const resNoExiste = await request(app.getHttpServer())
      .post('/auth/recuperar-password')
      .send({ nombre_usuario: 'NO-EXISTE-ESTA-CUENTA-T013' })
      .expect(200);

    expect(resExiste.body).toEqual(resNoExiste.body);
  });

  it('para profesor, el correo va a correoRecuperacion y no a correoElectronico (RF-02/RF-03)', async () => {
    const usuarioProfesor = 'TEST-T013-PROFESOR-CORREOS-DISTINTOS';
    await prisma.usuario.create({
      data: {
        nombreUsuario: usuarioProfesor,
        contrasenaHash: await bcrypt.hash('ClaveTemporalProfe1', 12),
        rol: 'profesor',
        // A propósito distintos: si el código usara correoElectronico por
        // error, esta prueba lo detectaría.
        correoElectronico: 'profesor.oficina@example.com',
        correoRecuperacion: 'profesor.recuperacion@example.com',
        debeCambiarContrasena: true,
      },
    });

    try {
      await request(app.getHttpServer())
        .post('/auth/recuperar-password')
        .send({ nombre_usuario: usuarioProfesor })
        .expect(200);

      const correo = await leerUltimaEntradaDelLog(usuarioProfesor);
      expect(correo.destinatario).toBe('profesor.recuperacion@example.com');
    } finally {
      await prisma.usuario.deleteMany({
        where: { nombreUsuario: usuarioProfesor },
      });
    }
  });

  it('rechaza un token inventado', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/restablecer-password')
      .send({
        token: 'esto-nunca-fue-un-token-real',
        contrasena_nueva: 'OtraClaveMas789',
      })
      .expect(400);

    expect(res.body.error.code).toBe('TOKEN_RESTABLECIMIENTO_INVALIDO');
  });

  it('rechaza un token ya expirado', async () => {
    await request(app.getHttpServer())
      .post('/auth/recuperar-password')
      .send({ nombre_usuario: USUARIO })
      .expect(200);
    const token = await leerUltimoTokenDelLog(USUARIO);

    // Forzamos la expiración directo en BD para no depender de esperar de verdad.
    await prisma.usuario.update({
      where: { nombreUsuario: USUARIO },
      data: { tokenRestablecimientoExpira: new Date(Date.now() - 1000) },
    });

    const res = await request(app.getHttpServer())
      .post('/auth/restablecer-password')
      .send({ token, contrasena_nueva: 'OtraClaveMas789' })
      .expect(400);

    expect(res.body.error.code).toBe('TOKEN_RESTABLECIMIENTO_INVALIDO');
  });

  it('un restablecimiento exitoso también apaga debe_cambiar_contrasena (mismo efecto que T-014)', async () => {
    const usuarioProfesor = 'TEST-T013-PROFESOR';
    await prisma.usuario.create({
      data: {
        nombreUsuario: usuarioProfesor,
        contrasenaHash: await bcrypt.hash('ClaveTemporalProfe1', 12),
        rol: 'profesor',
        correoElectronico: 'profesor.t013@example.com',
        correoRecuperacion: 'profesor.t013@example.com',
        debeCambiarContrasena: true,
      },
    });

    try {
      await request(app.getHttpServer())
        .post('/auth/recuperar-password')
        .send({ nombre_usuario: usuarioProfesor })
        .expect(200);
      const token = await leerUltimoTokenDelLog(usuarioProfesor);

      await request(app.getHttpServer())
        .post('/auth/restablecer-password')
        .send({ token, contrasena_nueva: 'ClaveDefinitivaProfe2' })
        .expect(200);

      const profesorActualizado = await prisma.usuario.findUniqueOrThrow({
        where: { nombreUsuario: usuarioProfesor },
      });
      expect(profesorActualizado.debeCambiarContrasena).toBe(false);
    } finally {
      await prisma.usuario.deleteMany({
        where: { nombreUsuario: usuarioProfesor },
      });
    }
  });
});

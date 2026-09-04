// T-015: RolesGuard todavía no protege ningún endpoint real (no existe
// /admin/* hasta la Fase 2). Estos controllers son solo para probar el guard
// en aislamiento, con la forma de ruta que sí va a tener /admin/* y un
// endpoint "datos de un alumno específico" — no son parte de la app real.
import {
  Controller,
  Get,
  INestApplication,
  Module,
  Param,
  UseGuards,
} from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import bcrypt from 'bcrypt';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';
import { AuthModule } from './../src/auth/auth.module.js';
import { ValidarPropioAlumno } from './../src/auth/decorators/validar-propio-alumno.decorator.js';
import { JwtAuthGuard } from './../src/auth/guards/jwt-auth.guard.js';
import { PrismaService } from './../src/prisma/prisma.service.js';

@Controller('admin')
class AdminDePruebaController {
  @Get('ping')
  ping() {
    return { ok: true };
  }
}

@Controller('alumnos-de-prueba')
class AlumnoDatosDePruebaController {
  // JwtAuthGuard exige sesión; @ValidarPropioAlumno (vía RolesGuard, global)
  // exige además que el id sea el propio, salvo que quien pregunta sea profesor.
  @Get(':id')
  @UseGuards(JwtAuthGuard)
  @ValidarPropioAlumno('id')
  obtener(@Param('id') id: string) {
    return { idConsultado: id };
  }
}

// JwtAuthGuard necesita JwtService, que vive en AuthModule — este módulo de
// prueba lo importa para que la resolución de dependencias funcione igual
// que en un módulo real de la Fase 2 (que también importaría AuthModule).
@Module({
  imports: [AuthModule],
  controllers: [AdminDePruebaController, AlumnoDatosDePruebaController],
})
class RolesGuardTestModule {}

describe('RolesGuard (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;

  const USUARIO_ALUMNO = 'TEST-T015-ALUMNO';
  const USUARIO_OTRO_ALUMNO = 'TEST-T015-OTRO-ALUMNO';
  const USUARIO_PROFESOR = 'TEST-T015-PROFESOR';
  const PASSWORD = 'ClaveDePrueba123';

  let idAlumno: number;
  let tokenAlumno: string;
  let tokenOtroAlumno: string;
  let tokenProfesor: string;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule, RolesGuardTestModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);

    const resAlumno = await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: USUARIO_ALUMNO,
        nombre: 'Paola',
        apellido_paterno: 'Cortés',
        apellido_materno: 'Duran',
        carrera: 'Ingeniería en Desarrollo de Software',
        semestre: 8,
        correo: 'paola@example.com',
        contrasena: PASSWORD,
        acepto_aviso_privacidad: true,
      })
      .expect(201);
    idAlumno = resAlumno.body.id;

    await request(app.getHttpServer())
      .post('/auth/registro')
      .send({
        matricula: USUARIO_OTRO_ALUMNO,
        nombre: 'Renata',
        apellido_paterno: 'Salas',
        apellido_materno: 'Vera',
        carrera: 'Ingeniería en Agroalimentos',
        semestre: 2,
        correo: 'renata@example.com',
        contrasena: PASSWORD,
        acepto_aviso_privacidad: true,
      })
      .expect(201);

    await prisma.usuario.create({
      data: {
        nombreUsuario: USUARIO_PROFESOR,
        contrasenaHash: await bcrypt.hash(PASSWORD, 12),
        rol: 'profesor',
        correoElectronico: 'profesor.t015@example.com',
        correoRecuperacion: 'profesor.t015@example.com',
        debeCambiarContrasena: false,
      },
    });

    async function login(nombre_usuario: string) {
      const res = await request(app.getHttpServer())
        .post('/auth/login')
        .send({ nombre_usuario, contrasena: PASSWORD })
        .expect(200);
      return res.body.access_token as string;
    }

    tokenAlumno = await login(USUARIO_ALUMNO);
    tokenOtroAlumno = await login(USUARIO_OTRO_ALUMNO);
    tokenProfesor = await login(USUARIO_PROFESOR);
  });

  afterEach(async () => {
    await prisma.perfilAlumno.deleteMany({
      where: {
        usuario: {
          nombreUsuario: { in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO] },
        },
      },
    });
    await prisma.usuario.deleteMany({
      where: {
        nombreUsuario: {
          in: [USUARIO_ALUMNO, USUARIO_OTRO_ALUMNO, USUARIO_PROFESOR],
        },
      },
    });
    await app.close();
  });

  describe('RNF-07: /admin/* exclusivo de profesor', () => {
    it('bloquea sin sesión', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/ping')
        .expect(401);
      expect(res.body.error.code).toBe('SESION_REQUERIDA');
    });

    it('bloquea a un alumno con sesión válida', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/ping')
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .expect(403);
      expect(res.body.error.code).toBe('ADMIN_SOLO_PROFESOR');
    });

    it('permite a un profesor', async () => {
      const res = await request(app.getHttpServer())
        .get('/admin/ping')
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);
      expect(res.body).toEqual({ ok: true });
    });
  });

  describe('RNF-08: un alumno solo ve sus propios datos', () => {
    it('un alumno puede consultar su propio id', async () => {
      const res = await request(app.getHttpServer())
        .get(`/alumnos-de-prueba/${idAlumno}`)
        .set('Authorization', `Bearer ${tokenAlumno}`)
        .expect(200);
      expect(res.body).toEqual({ idConsultado: String(idAlumno) });
    });

    it('un alumno NO puede consultar el id de otro alumno', async () => {
      const res = await request(app.getHttpServer())
        .get(`/alumnos-de-prueba/${idAlumno}`)
        .set('Authorization', `Bearer ${tokenOtroAlumno}`)
        .expect(403);
      expect(res.body.error.code).toBe('SOLO_PROPIOS_DATOS');
    });

    it('un profesor puede consultar el id de cualquier alumno', async () => {
      const res = await request(app.getHttpServer())
        .get(`/alumnos-de-prueba/${idAlumno}`)
        .set('Authorization', `Bearer ${tokenProfesor}`)
        .expect(200);
      expect(res.body).toEqual({ idConsultado: String(idAlumno) });
    });

    it('sin sesión, JwtAuthGuard ya lo bloquea antes de llegar al chequeo de dueño', async () => {
      const res = await request(app.getHttpServer())
        .get(`/alumnos-de-prueba/${idAlumno}`)
        .expect(401);
      expect(res.body.error.code).toBe('SESION_REQUERIDA');
    });
  });

  describe('rutas normales: RolesGuard no interfiere', () => {
    it('/auth/login sigue siendo público (no es /admin ni tiene el decorador)', async () => {
      await request(app.getHttpServer())
        .post('/auth/login')
        .send({ nombre_usuario: USUARIO_ALUMNO, contrasena: PASSWORD })
        .expect(200);
    });

    it('/ (ruta raíz existente) sigue funcionando sin sesión', async () => {
      await request(app.getHttpServer()).get('/').expect(200);
    });
  });
});

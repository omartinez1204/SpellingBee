import { createHash, randomBytes } from 'node:crypto';
import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import bcrypt from 'bcrypt';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import { Prisma } from '../generated/prisma/client.js';
import {
  MAIL_SERVICE,
  type MailService,
} from '../mail/mail.service.interface.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CambiarPasswordDto } from './dto/cambiar-password.dto.js';
import type { LoginDto } from './dto/login.dto.js';
import type { RecuperarPasswordDto } from './dto/recuperar-password.dto.js';
import type { RegistroAlumnoDto } from './dto/registro-alumno.dto.js';
import type { RestablecerPasswordDto } from './dto/restablecer-password.dto.js';

const BCRYPT_COST = 12;

// El ERS no fija una duración para el token de restablecimiento (RF-03);
// 30 min es un default corto [decisión de equipo], no un requisito del cliente.
const TOKEN_RESTABLECIMIENTO_TTL_MIN = 30;

function hashToken(tokenEnClaro: string): string {
  // sha256 (no bcrypt): el token ya es aleatorio de alta entropía, no un
  // secreto elegido por una persona — no necesita un hash lento.
  return createHash('sha256').update(tokenEnClaro).digest('hex');
}

// Hash "señuelo": si el usuario no existe, igual corremos un bcrypt.compare
// contra esto en vez de responder de inmediato. Sin esto, un login a un
// nombre_usuario inexistente respondería notablemente más rápido que uno con
// contraseña incorrecta, y ese tiempo de respuesta ya filtra si la cuenta existe.
const HASH_SENUELO = bcrypt.hashSync('ninguna-cuenta-usa-esto', BCRYPT_COST);

function errorMatriculaDuplicada(): DominioException {
  return new DominioException(
    'MATRICULA_DUPLICADA',
    'Ya existe una cuenta con esa matrícula.',
    HttpStatus.CONFLICT,
  );
}

function errorCredencialesInvalidas(): DominioException {
  // A propósito el mismo code/mensaje exista o no el nombre_usuario, sin decir
  // cuál de los dos falló (RF-01/RF-02) — evita enumerar cuentas válidas.
  return new DominioException(
    'CREDENCIALES_INVALIDAS',
    'Usuario o contraseña incorrectos.',
    HttpStatus.UNAUTHORIZED,
  );
}

function errorTokenInvalido(): DominioException {
  return new DominioException(
    'TOKEN_RESTABLECIMIENTO_INVALIDO',
    'El enlace de restablecimiento no es válido o ya expiró.',
    HttpStatus.BAD_REQUEST,
  );
}

function errorContrasenaActualIncorrecta(): DominioException {
  // Aquí sí se puede ser específico (a diferencia de login/recuperar): la
  // identidad ya está probada por el JWT, no hay nada que enumerar.
  return new DominioException(
    'CONTRASENA_ACTUAL_INCORRECTA',
    'La contraseña actual no es correcta.',
    HttpStatus.BAD_REQUEST,
  );
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    @Inject(MAIL_SERVICE) private readonly mailService: MailService,
  ) {}

  async registrarAlumno(dto: RegistroAlumnoDto) {
    const yaExiste = await this.prisma.usuario.findUnique({
      where: { nombreUsuario: dto.matricula },
    });
    if (yaExiste) {
      throw errorMatriculaDuplicada();
    }

    const contrasenaHash = await bcrypt.hash(dto.contrasena, BCRYPT_COST);

    try {
      return await this.prisma.usuario.create({
        data: {
          nombreUsuario: dto.matricula,
          contrasenaHash,
          rol: 'alumno',
          correoElectronico: dto.correo,
          debeCambiarContrasena: false,
          perfilAlumno: {
            create: {
              nombre: dto.nombre,
              apellidoPaterno: dto.apellido_paterno,
              apellidoMaterno: dto.apellido_materno,
              carrera: dto.carrera,
              semestre: dto.semestre,
            },
          },
        },
        select: {
          id: true,
          nombreUsuario: true,
          rol: true,
        },
      });
    } catch (error) {
      // Carrera contra otra petición simultánea con la misma matrícula:
      // el check de arriba no la vio, pero la constraint única de la BD sí.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw errorMatriculaDuplicada();
      }
      throw error;
    }
  }

  async login(dto: LoginDto) {
    // Mismo endpoint y misma columna para alumno (matrícula) y profesor
    // (username): Usuario.nombreUsuario ya cubre ambos casos (RF-01/RF-02).
    const usuario = await this.prisma.usuario.findUnique({
      where: { nombreUsuario: dto.nombre_usuario },
    });

    const coincide = await bcrypt.compare(
      dto.contrasena,
      usuario?.contrasenaHash ?? HASH_SENUELO,
    );

    if (!usuario || !coincide) {
      throw errorCredencialesInvalidas();
    }

    const payload = {
      sub: usuario.id,
      rol: usuario.rol,
      debe_cambiar_contrasena: usuario.debeCambiarContrasena,
    };

    return {
      access_token: await this.jwtService.signAsync(payload),
      rol: usuario.rol,
      debe_cambiar_contrasena: usuario.debeCambiarContrasena,
    };
  }

  logout() {
    // RF-04: sesión stateless con JWT (diseno-tecnico.md §1) — esta versión
    // no lleva lista de tokens invalidados, así que no hay nada que borrar ni
    // marcar del lado del servidor. "Cerrar sesión" es que el cliente
    // descarte el JWT que tiene guardado; este endpoint solo le da a RF-04
    // una ruta real que llamar (y un lugar fijo si algún día sí hace falta
    // invalidar tokens del lado del servidor).
    return { mensaje: 'Sesión cerrada. El cliente debe descartar el JWT.' };
  }

  async recuperarPassword(dto: RecuperarPasswordDto) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { nombreUsuario: dto.nombre_usuario },
    });

    // Mismo mensaje exista o no la cuenta (igual que login, RF-01/RF-02):
    // este endpoint no debe servir para averiguar qué matrículas/usernames
    // son válidos. Solo si el usuario existe de verdad se genera un token y
    // se manda el correo; si no, no se hace nada más.
    if (usuario) {
      const tokenEnClaro = randomBytes(32).toString('hex');
      const expira = new Date(
        Date.now() + TOKEN_RESTABLECIMIENTO_TTL_MIN * 60 * 1000,
      );

      await this.prisma.usuario.update({
        where: { id: usuario.id },
        data: {
          tokenRestablecimiento: hashToken(tokenEnClaro),
          tokenRestablecimientoExpira: expira,
        },
      });

      // Destino RF-03: el correo de recuperación si existe (siempre el caso
      // en profesor, RF-02), o el correo de la cuenta si no (siempre el caso
      // en alumno, RF-01 — ahí no hay un correo de recuperación aparte).
      const destinatario =
        usuario.correoRecuperacion ?? usuario.correoElectronico;
      await this.mailService.enviarCorreoRestablecimiento(
        destinatario,
        usuario.nombreUsuario,
        tokenEnClaro,
      );
    }

    return {
      mensaje:
        'Si existe una cuenta con ese nombre de usuario, se envió un correo con instrucciones para restablecer la contraseña.',
    };
  }

  async restablecerPassword(dto: RestablecerPasswordDto) {
    const usuario = await this.prisma.usuario.findFirst({
      where: { tokenRestablecimiento: hashToken(dto.token) },
    });

    if (
      !usuario ||
      !usuario.tokenRestablecimientoExpira ||
      usuario.tokenRestablecimientoExpira < new Date()
    ) {
      throw errorTokenInvalido();
    }

    const contrasenaHash = await bcrypt.hash(dto.contrasena_nueva, BCRYPT_COST);

    await this.prisma.usuario.update({
      where: { id: usuario.id },
      data: {
        contrasenaHash,
        // Un solo uso: se limpia aunque el reset haya sido exitoso, para que
        // el mismo enlace no sirva dos veces (RF-03).
        tokenRestablecimiento: null,
        tokenRestablecimientoExpira: null,
        // Restablecer la contraseña por este camino satisface la misma
        // obligación que /auth/cambiar-password (T-014, RF-36): ya no debe
        // forzarse un cambio si la persona acaba de fijar una nueva.
        debeCambiarContrasena: false,
      },
    });

    return { mensaje: 'Contraseña restablecida correctamente.' };
  }

  async cambiarPassword(idUsuario: number, dto: CambiarPasswordDto) {
    // idUsuario viene del JWT (JwtAuthGuard + @CurrentUser), nunca del body:
    // un usuario con sesión solo puede cambiar SU PROPIA contraseña.
    const usuario = await this.prisma.usuario.findUniqueOrThrow({
      where: { id: idUsuario },
    });

    const actualCoincide = await bcrypt.compare(
      dto.contrasena_actual,
      usuario.contrasenaHash,
    );
    if (!actualCoincide) {
      throw errorContrasenaActualIncorrecta();
    }

    const contrasenaHash = await bcrypt.hash(dto.contrasena_nueva, BCRYPT_COST);

    await this.prisma.usuario.update({
      where: { id: idUsuario },
      data: {
        contrasenaHash,
        // RF-36: si la cuenta tenía que cambiar su contraseña asignada, este
        // cambio exitoso ya cumplió esa obligación.
        debeCambiarContrasena: false,
      },
    });

    return { mensaje: 'Contraseña actualizada correctamente.' };
  }
}

import { HttpStatus, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import bcrypt from 'bcrypt';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import { Prisma } from '../generated/prisma/client.js';
import { PrismaService } from '../prisma/prisma.service.js';
import type { LoginDto } from './dto/login.dto.js';
import type { RegistroAlumnoDto } from './dto/registro-alumno.dto.js';

const BCRYPT_COST = 12;

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

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
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
}

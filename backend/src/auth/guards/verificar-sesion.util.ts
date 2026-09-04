import { HttpStatus } from '@nestjs/common';
import type { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';
import { DominioException } from '../../common/exceptions/dominio.exception.js';

// Payload firmado en AuthService.login() (T-011): sub, rol, debe_cambiar_contrasena.
export interface JwtPayload {
  sub: number;
  rol: string;
  debe_cambiar_contrasena: boolean;
}

// Express no declara `user` en Request; lo tipamos aquí en vez de una
// declaración global de módulo, que es más fácil de perder de vista.
export interface RequestConUsuario extends Request {
  user: JwtPayload;
}

export function errorSinSesion(): DominioException {
  return new DominioException(
    'SESION_REQUERIDA',
    'Debes iniciar sesión para hacer esto.',
    HttpStatus.UNAUTHORIZED,
  );
}

function extraerToken(request: Request): string | undefined {
  const [tipo, token] = (request.headers.authorization ?? '').split(' ');
  return tipo === 'Bearer' ? token : undefined;
}

// Compartido entre JwtAuthGuard (T-014) y RolesGuard (T-015): ambos necesitan
// exactamente la misma verificación de JWT, solo que la usan para cosas
// distintas después (uno solo exige sesión, el otro además revisa rol/dueño).
export async function verificarSesion(
  request: RequestConUsuario,
  jwtService: JwtService,
): Promise<JwtPayload> {
  const token = extraerToken(request);
  if (!token) {
    throw errorSinSesion();
  }

  try {
    request.user = await jwtService.verifyAsync<JwtPayload>(token);
  } catch {
    throw errorSinSesion();
  }

  return request.user;
}

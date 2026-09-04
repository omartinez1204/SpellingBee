import {
  CanActivate,
  ExecutionContext,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
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

function errorSinSesion(): DominioException {
  return new DominioException(
    'SESION_REQUERIDA',
    'Debes iniciar sesión para hacer esto.',
    HttpStatus.UNAUTHORIZED,
  );
}

// Guard de AUTENTICACIÓN: solo confirma que el JWT es válido y expone su
// payload en request.user. No decide permisos por rol — eso es el
// RolesGuard de T-015, que se apoya en este guard, no lo reemplaza.
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwtService: JwtService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestConUsuario>();
    const token = this.extraerToken(request);
    if (!token) {
      throw errorSinSesion();
    }

    try {
      request.user = await this.jwtService.verifyAsync<JwtPayload>(token);
    } catch {
      throw errorSinSesion();
    }

    return true;
  }

  private extraerToken(request: Request): string | undefined {
    const [tipo, token] = (request.headers.authorization ?? '').split(' ');
    return tipo === 'Bearer' ? token : undefined;
  }
}

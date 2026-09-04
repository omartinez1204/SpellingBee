import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  type RequestConUsuario,
  verificarSesion,
} from './verificar-sesion.util.js';

export type { JwtPayload, RequestConUsuario } from './verificar-sesion.util.js';

// Guard de AUTENTICACIÓN: solo confirma que el JWT es válido y expone su
// payload en request.user. No decide permisos por rol — eso es el
// RolesGuard de T-015, que se apoya en la misma verificación, no la repite.
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwtService: JwtService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestConUsuario>();
    await verificarSesion(request, this.jwtService);
    return true;
  }
}

import {
  CanActivate,
  ExecutionContext,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { DominioException } from '../../common/exceptions/dominio.exception.js';
import { VALIDAR_PROPIO_ALUMNO_KEY } from '../decorators/validar-propio-alumno.decorator.js';
import {
  type RequestConUsuario,
  verificarSesion,
} from './verificar-sesion.util.js';

const RUTA_ADMIN = /^\/admin(\/|$)/;

function errorSoloProfesor(): DominioException {
  return new DominioException(
    'ADMIN_SOLO_PROFESOR',
    'Esta ruta es exclusiva para profesores.',
    HttpStatus.FORBIDDEN,
  );
}

function errorSoloPropiosDatos(): DominioException {
  return new DominioException(
    'SOLO_PROPIOS_DATOS',
    'No puedes consultar datos de otro alumno.',
    HttpStatus.FORBIDDEN,
  );
}

// Guard de AUTORIZACIÓN, global (registrado como APP_GUARD en app.module.ts
// para que ninguna ruta /admin/* quede protegida "si alguien se acuerda" de
// ponerle el decorador). Dos reglas independientes:
//
//  (1) RNF-07: cualquier ruta bajo /admin/* exige rol profesor.
//  (2) RNF-08: una ruta marcada con @ValidarPropioAlumno(campo) exige que el
//      id de alumno solicitado sea el del propio JWT, salvo que quien
//      pregunta sea profesor.
//
// Para rutas que no son ninguna de las dos cosas, este guard no hace nada
// (ni siquiera exige sesión) — eso lo sigue decidiendo cada ruta con
// JwtAuthGuard (T-014) si lo necesita.
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestConUsuario>();
    const esRutaAdmin = RUTA_ADMIN.test(request.path);
    const campoIdAlumno = this.reflector.getAllAndOverride<string | undefined>(
      VALIDAR_PROPIO_ALUMNO_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!esRutaAdmin && !campoIdAlumno) {
      return true;
    }

    const usuario = await verificarSesion(request, this.jwtService);

    if (esRutaAdmin && usuario.rol !== 'profesor') {
      throw errorSoloProfesor();
    }

    if (campoIdAlumno && usuario.rol !== 'profesor') {
      const idSolicitado =
        request.params[campoIdAlumno] ?? request.query[campoIdAlumno];
      if (String(idSolicitado) !== String(usuario.sub)) {
        throw errorSoloPropiosDatos();
      }
    }

    return true;
  }
}

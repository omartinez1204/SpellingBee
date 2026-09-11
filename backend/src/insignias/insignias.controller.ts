import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator.js';
import { JwtAuthGuard, type JwtPayload } from '../auth/guards/jwt-auth.guard.js';
import { InsigniasService } from './insignias.service.js';

// RF-24 (T-047). No es /admin/* ni usa @ValidarPropioAlumno: siempre
// contesta sobre EL PROPIO alumno de la sesión (usuario.sub) — mismo patrón
// que RachaController/PracticaController.
@Controller('progreso')
export class InsigniasController {
  constructor(private readonly insigniasService: InsigniasService) {}

  @Get('insignias')
  @UseGuards(JwtAuthGuard)
  obtenerInsignias(@CurrentUser() usuario: JwtPayload) {
    return this.insigniasService.obtenerInsigniasDeAlumno(usuario.sub);
  }
}

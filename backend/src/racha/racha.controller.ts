import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator.js';
import { JwtAuthGuard, type JwtPayload } from '../auth/guards/jwt-auth.guard.js';
import { RachaQueryDto } from './dto/racha-query.dto.js';
import { RachaService } from './racha.service.js';

// RF-23 (T-046). No es /admin/* ni usa @ValidarPropioAlumno: siempre
// contesta sobre EL PROPIO alumno de la sesión (usuario.sub) — mismo
// patrón que PracticaController.
@Controller('racha')
export class RachaController {
  constructor(private readonly rachaService: RachaService) {}

  @Get()
  @UseGuards(JwtAuthGuard)
  obtenerRacha(
    @Query() query: RachaQueryDto,
    @CurrentUser() usuario: JwtPayload,
  ) {
    return this.rachaService.obtenerRachaActual(usuario.sub, query.fecha_local);
  }
}

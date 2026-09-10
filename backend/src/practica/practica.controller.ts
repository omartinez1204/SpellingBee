import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator.js';
import { JwtAuthGuard, type JwtPayload } from '../auth/guards/jwt-auth.guard.js';
import { PracticaService } from './practica.service.js';

// RF-22 (T-042). No es una ruta /admin/* ni usa @ValidarPropioAlumno: no
// recibe ningún id de alumno por parámetro — siempre contesta sobre EL
// PROPIO alumno de la sesión (usuario.sub), así que RolesGuard (global) no
// tendría nada que validar aquí por su cuenta. @UseGuards(JwtAuthGuard) es
// necesario para que exista sesión y @CurrentUser() tenga qué leer — mismo
// patrón que PATCH /auth/cambiar-password.
@Controller('practica')
export class PracticaController {
  constructor(private readonly practicaService: PracticaService) {}

  @Get('mejor-tiempo/:idPalabra')
  @UseGuards(JwtAuthGuard)
  obtenerMejorTiempo(
    @Param('idPalabra') idPalabra: string,
    @CurrentUser() usuario: JwtPayload,
  ) {
    return this.practicaService.obtenerMejorTiempo(usuario.sub, idPalabra);
  }
}

import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator.js';
import { JwtAuthGuard, type JwtPayload } from '../auth/guards/jwt-auth.guard.js';
import { GuardarPracticaDto } from './dto/guardar-practica.dto.js';
import { SincronizarPracticaDto } from './dto/sincronizar-practica.dto.js';
import { PracticaService } from './practica.service.js';

// RF-21/RF-22/RF-27 (T-042/T-045). Ninguna ruta de este controlador es
// /admin/* ni usa @ValidarPropioAlumno: ninguna recibe un id de alumno por
// parámetro — ambas actúan siempre sobre EL PROPIO alumno de la sesión
// (usuario.sub), así que RolesGuard (global) no tendría nada que validar
// aquí por su cuenta. @UseGuards(JwtAuthGuard) es necesario para que exista
// sesión y @CurrentUser() tenga qué leer — mismo patrón que PATCH
// /auth/cambiar-password.
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

  // RF-21, RF-27 (T-045). Sin @HttpCode: el default de @Post() (201) es
  // correcto — esto sí crea un recurso nuevo, a diferencia de /auth/login.
  @Post()
  @UseGuards(JwtAuthGuard)
  guardarPractica(
    @CurrentUser() usuario: JwtPayload,
    @Body() dto: GuardarPracticaDto,
  ) {
    return this.practicaService.guardarPractica(usuario.sub, dto);
  }

  // T-063 (RF-33). 200, no el 201 por default de @Post(): esto no crea "un"
  // recurso — es una operación de sincronización en lote, idempotente, que
  // puede terminar creando cero registros nuevos (si todos ya existían).
  @Post('sync')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  sincronizarLote(
    @CurrentUser() usuario: JwtPayload,
    @Body() dto: SincronizarPracticaDto,
  ) {
    return this.practicaService.sincronizarLote(usuario.sub, dto);
  }
}

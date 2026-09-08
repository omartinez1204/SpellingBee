import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator.js';
import type { JwtPayload } from '../auth/guards/jwt-auth.guard.js';
import { PaginacionDto } from '../common/dto/paginacion.dto.js';
import { AdminPalabrasService } from './admin-palabras.service.js';
import { CrearPalabraDto } from './dto/crear-palabra.dto.js';
import { EditarPalabraDto } from './dto/editar-palabra.dto.js';
import { OcultarPalabraDto } from './dto/ocultar-palabra.dto.js';

// RF-08 a RF-10, RF-39. Protegido por RolesGuard (T-015), registrado GLOBAL
// vía APP_GUARD en app.module.ts: cualquier ruta bajo /admin/* ya exige rol
// profesor sin necesidad de un @UseGuards aquí, y ese mismo guard deja
// request.user listo para @CurrentUser() (ambos comparten verificarSesion()).
// No incluye RF-11 (subida de audio) — eso es T-025.
@Controller('admin/palabras')
export class AdminPalabrasController {
  constructor(private readonly adminPalabrasService: AdminPalabrasService) {}

  @Get()
  listar(@Query() query: PaginacionDto) {
    return this.adminPalabrasService.listar(query);
  }

  @Post()
  crear(@Body() dto: CrearPalabraDto, @CurrentUser() usuario: JwtPayload) {
    return this.adminPalabrasService.crear(dto, usuario.sub);
  }

  @Patch(':id')
  @HttpCode(HttpStatus.OK)
  editar(@Param('id') id: string, @Body() dto: EditarPalabraDto) {
    return this.adminPalabrasService.editar(id, dto);
  }

  @Patch(':id/ocultar')
  @HttpCode(HttpStatus.OK)
  ocultar(@Param('id') id: string, @Body() dto: OcultarPalabraDto) {
    return this.adminPalabrasService.ocultar(id, dto);
  }
}

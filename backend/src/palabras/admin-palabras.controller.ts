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
  UploadedFile,
  UseFilters,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { CurrentUser } from '../auth/decorators/current-user.decorator.js';
import type { JwtPayload } from '../auth/guards/jwt-auth.guard.js';
import { PaginacionDto } from '../common/dto/paginacion.dto.js';
import { AdminPalabrasService } from './admin-palabras.service.js';
import { ArchivoDemasiadoGrandeFilter } from './archivo-demasiado-grande.filter.js';
import { CrearPalabraDto } from './dto/crear-palabra.dto.js';
import { EditarPalabraDto } from './dto/editar-palabra.dto.js';
import { OcultarPalabraDto } from './dto/ocultar-palabra.dto.js';

// Límite del propio Multer: es solo una red de seguridad contra un cliente
// abusivo (memoryStorage no debe bufferear archivos enormes); el límite de
// negocio real de 1 MB (RF-11) lo valida AdminPalabrasService con un mensaje
// en español, no este límite crudo de multer.
const LIMITE_MULTER_BYTES = 5 * 1024 * 1024;

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

  // RF-11. Campo del multipart: "audio".
  @Post(':id/audio')
  // T-071: el límite crudo de multer responde con el mismo error de negocio
  // de 1 MB (en español), no con "File too large".
  @UseFilters(ArchivoDemasiadoGrandeFilter)
  @UseInterceptors(
    FileInterceptor('audio', {
      storage: memoryStorage(),
      limits: { fileSize: LIMITE_MULTER_BYTES },
    }),
  )
  subirAudio(
    @Param('id') id: string,
    @UploadedFile() archivo: Express.Multer.File | undefined,
  ) {
    return this.adminPalabrasService.subirAudio(id, archivo);
  }
}

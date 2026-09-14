import { Controller, Get, Param, Query } from '@nestjs/common';
import { FiltrosAlumnosDto } from './dto/filtros-alumnos.dto.js';
import { AdminAlumnosService } from './admin-alumnos.service.js';

// RF-28, RF-29, RF-30. Protegido por RolesGuard (T-015), registrado GLOBAL
// vía APP_GUARD en app.module.ts: cualquier ruta bajo /admin/* ya exige rol
// profesor sin necesidad de un @UseGuards aquí (mismo patrón que
// AdminPalabrasController).
@Controller('admin/alumnos')
export class AdminAlumnosController {
  constructor(private readonly adminAlumnosService: AdminAlumnosService) {}

  @Get()
  listar(@Query() query: FiltrosAlumnosDto) {
    return this.adminAlumnosService.listar(query);
  }

  @Get(':id')
  detalle(@Param('id') id: string, @Query() query: FiltrosAlumnosDto) {
    return this.adminAlumnosService.detalle(id, query);
  }
}

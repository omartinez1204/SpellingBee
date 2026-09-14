import { Controller, Get, Query } from '@nestjs/common';
import { PaginacionDto } from '../common/dto/paginacion.dto.js';
import { AdminAlumnosService } from './admin-alumnos.service.js';

// RF-28. Protegido por RolesGuard (T-015), registrado GLOBAL vía APP_GUARD
// en app.module.ts: cualquier ruta bajo /admin/* ya exige rol profesor sin
// necesidad de un @UseGuards aquí (mismo patrón que AdminPalabrasController).
@Controller('admin/alumnos')
export class AdminAlumnosController {
  constructor(private readonly adminAlumnosService: AdminAlumnosService) {}

  @Get()
  listar(@Query() query: PaginacionDto) {
    return this.adminAlumnosService.listar(query);
  }
}

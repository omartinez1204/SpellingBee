import { Controller, Get, Param, Query } from '@nestjs/common';
import { PaginacionDto } from '../common/dto/paginacion.dto.js';
import { NivelesService } from './niveles.service.js';

// RF-05/RF-06/RF-31. Las 3 rutas públicas a propósito: diseno-tecnico.md
// §3.2/§3.6 no las marca como protegidas (a diferencia de §3.3/§3.5, que sí
// dicen explícitamente "requiere rol profesor"), y el criterio de aceptación
// de RF-05 es que el alumno los vea "al entrar a la sección de práctica",
// sin mencionar sesión iniciada.
@Controller('niveles')
export class NivelesController {
  constructor(private readonly nivelesService: NivelesService) {}

  @Get()
  listar() {
    return this.nivelesService.listar();
  }

  // RNF-12 (T-070): paginado con ?pagina=&limite= (defecto 20, tope 50).
  @Get(':id/palabras')
  listarPalabras(@Param('id') id: string, @Query() query: PaginacionDto) {
    return this.nivelesService.listarPalabras(id, query);
  }

  @Get(':id/descarga')
  descargarNivel(@Param('id') id: string) {
    return this.nivelesService.descargarNivel(id);
  }
}

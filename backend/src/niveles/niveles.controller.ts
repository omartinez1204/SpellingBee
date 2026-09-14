import { Controller, Get, Param } from '@nestjs/common';
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

  @Get(':id/palabras')
  listarPalabras(@Param('id') id: string) {
    return this.nivelesService.listarPalabras(id);
  }

  @Get(':id/descarga')
  descargarNivel(@Param('id') id: string) {
    return this.nivelesService.descargarNivel(id);
  }
}

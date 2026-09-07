import { Controller, Get } from '@nestjs/common';
import { NivelesService } from './niveles.service.js';

// RF-05. Pública a propósito: diseno-tecnico.md §3.2 no la marca como
// protegida (a diferencia de §3.3/§3.5, que sí dicen explícitamente "requiere
// rol profesor") y el propio criterio de aceptación es que el alumno los vea
// "al entrar a la sección de práctica", sin mencionar sesión iniciada.
@Controller('niveles')
export class NivelesController {
  constructor(private readonly nivelesService: NivelesService) {}

  @Get()
  listar() {
    return this.nivelesService.listar();
  }
}

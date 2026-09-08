import { Controller, Get, Param } from '@nestjs/common';
import { PalabrasService } from './palabras.service.js';

// RF-07. Pública a propósito, igual que /niveles y /niveles/:id/palabras
// (T-020/T-021): diseno-tecnico.md §3.2 no la marca como protegida.
@Controller('palabras')
export class PalabrasController {
  constructor(private readonly palabrasService: PalabrasService) {}

  @Get(':id')
  obtenerDetalle(@Param('id') id: string) {
    return this.palabrasService.obtenerDetalle(id);
  }
}

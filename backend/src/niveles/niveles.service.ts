import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';

@Injectable()
export class NivelesService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-05: los 3 niveles, en el orden fijo Fácil/Intermedio/Difícil.
  listar() {
    return this.prisma.nivel.findMany({
      orderBy: { orden: 'asc' },
      select: { id: true, nombre: true, orden: true },
    });
  }
}

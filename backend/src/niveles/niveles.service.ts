import { HttpStatus, Injectable } from '@nestjs/common';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { PrismaService } from '../prisma/prisma.service.js';

function errorNivelIdInvalido(): DominioException {
  return new DominioException(
    'NIVEL_ID_INVALIDO',
    'El id de nivel debe ser un número entero positivo.',
    HttpStatus.BAD_REQUEST,
  );
}

export function errorNivelNoEncontrado(): DominioException {
  return new DominioException(
    'NIVEL_NO_ENCONTRADO',
    'No existe un nivel con ese id.',
    HttpStatus.NOT_FOUND,
  );
}

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

  // RF-06: solo palabras completa=true AND oculta=false del nivel indicado.
  // completa todavía no se recalcula automáticamente (eso es T-022, no este
  // endpoint) — por ahora depende del default de esquema
  // (Palabra.completa @default(false), ver migration.sql), así que ninguna de
  // las 45 palabras del catálogo (sin significado/oración/audio capturados
  // aún, T-003 bloqueado) puede aparecer aquí todavía. Una lista vacía en
  // este momento es el resultado correcto, no un error.
  async listarPalabras(idNivelParam: string) {
    const idNivel = parsearIdDeRuta(idNivelParam);
    if (idNivel === null) {
      throw errorNivelIdInvalido();
    }

    const nivel = await this.prisma.nivel.findUnique({
      where: { id: idNivel },
    });
    if (!nivel) {
      throw errorNivelNoEncontrado();
    }

    // Campos mínimos [decisión de equipo, a confirmar]: ni diseno-tecnico.md
    // ni el ERS fijan la forma de esta lista. significado_es/oracion_ejemplo
    // se excluyen a propósito (RF-07: quedan ocultos tras pistas, el detalle
    // completo es GET /palabras/:id de T-023). nombre_archivo_audio también
    // se deja fuera de esta lista por ahora, ya que RF-07 lo asocia a la
    // pantalla de práctica de UNA palabra ya elegida, no a este listado.
    return this.prisma.palabra.findMany({
      where: { idNivel, completa: true, oculta: false },
      select: { id: true, texto: true },
    });
  }
}

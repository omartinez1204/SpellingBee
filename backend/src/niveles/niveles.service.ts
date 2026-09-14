import { HttpStatus, Injectable } from '@nestjs/common';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { urlAudio } from '../palabras/palabras.service.js';
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

  // RF-31 (T-060): paquete completo de un nivel para práctica sin conexión.
  // Mismo filtro completa=true AND oculta=false que RF-06 (listarPalabras),
  // pero aquí sí va el detalle completo de cada palabra (no solo id/texto):
  // RF-32 exige que el alumno pueda "ver palabra, reproducir audio,
  // deletrear y escribir oración" sin conexión usando SOLO lo descargado
  // aquí, así que significado_es/oracion_ejemplo/url_audio tienen que venir
  // — es el mismo shape que GET /palabras/:id (T-023), reutilizando su
  // mismo urlAudio() para no duplicar la convención de ruta del archivo.
  // completa=true garantiza (por el trigger de BD, ver schema.prisma) que
  // nombreArchivoAudio nunca es null aquí, así que url_audio tampoco lo es.
  //
  // Pública a propósito, mismo criterio que /niveles y /niveles/:id/palabras
  // (diseno-tecnico.md §3.2 no la marca como protegida, a diferencia de
  // §3.3/§3.5) — RF-31 tampoco la condiciona a sesión iniciada.
  //
  // Sin paginar [decisión de equipo, a confirmar]: a diferencia de
  // /admin/alumnos (RNF-12, listas sin cota conocida), esto es un paquete
  // pensado para descargarse COMPLETO de una sola vez y cachearse offline
  // (diseno-tecnico.md §3.6) — partirlo en páginas iría en contra del
  // propósito del endpoint. El catálogo actual (45 palabras/3 niveles) queda
  // muy por debajo del umbral de RNF-12 de cualquier forma.
  async descargarNivel(idNivelParam: string) {
    const idNivel = parsearIdDeRuta(idNivelParam);
    if (idNivel === null) {
      throw errorNivelIdInvalido();
    }

    const nivel = await this.prisma.nivel.findUnique({
      where: { id: idNivel },
      select: { id: true, nombre: true, orden: true },
    });
    if (!nivel) {
      throw errorNivelNoEncontrado();
    }

    const palabras = await this.prisma.palabra.findMany({
      where: { idNivel, completa: true, oculta: false },
      orderBy: { id: 'asc' },
      select: {
        id: true,
        texto: true,
        significadoEs: true,
        oracionEjemplo: true,
        nombreArchivoAudio: true,
      },
    });

    return {
      nivel,
      palabras: palabras.map((palabra) => ({
        id: palabra.id,
        texto: palabra.texto,
        significado_es: palabra.significadoEs,
        oracion_ejemplo: palabra.oracionEjemplo,
        url_audio: urlAudio(palabra.nombreArchivoAudio),
      })),
    };
  }
}

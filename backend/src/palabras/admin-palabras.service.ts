import { Injectable } from '@nestjs/common';
import { PaginacionDto } from '../common/dto/paginacion.dto.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { errorNivelNoEncontrado } from '../niveles/niveles.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { CrearPalabraDto } from './dto/crear-palabra.dto.js';
import { EditarPalabraDto } from './dto/editar-palabra.dto.js';
import { OcultarPalabraDto } from './dto/ocultar-palabra.dto.js';
import {
  errorPalabraIdInvalido,
  errorPalabraNoEncontrada,
  urlAudio,
} from './palabras.service.js';

const SELECT_ADMIN = {
  id: true,
  texto: true,
  idNivel: true,
  significadoEs: true,
  oracionEjemplo: true,
  nombreArchivoAudio: true,
  completa: true,
  oculta: true,
  fechaAlta: true,
  idProfesorAutor: true,
} as const;

type FilaAdmin = {
  id: number;
  texto: string;
  idNivel: number;
  significadoEs: string | null;
  oracionEjemplo: string | null;
  nombreArchivoAudio: string | null;
  completa: boolean;
  oculta: boolean;
  fechaAlta: Date;
  idProfesorAutor: number;
};

function aRespuestaAdmin(p: FilaAdmin) {
  return {
    id: p.id,
    texto: p.texto,
    id_nivel: p.idNivel,
    significado_es: p.significadoEs,
    oracion_ejemplo: p.oracionEjemplo,
    url_audio: urlAudio(p.nombreArchivoAudio),
    completa: p.completa,
    oculta: p.oculta,
    fecha_alta: p.fechaAlta,
    id_profesor_autor: p.idProfesorAutor,
  };
}

@Injectable()
export class AdminPalabrasService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-39: TODAS las palabras (completas/incompletas, ocultas/visibles), a
  // diferencia de GET /niveles/:id/palabras (T-021) que solo muestra las
  // listas para practicar. Paginado (RNF-12): nunca trae más de "limite"
  // (tope 50) filas en una sola consulta.
  async listar(query: PaginacionDto) {
    const { pagina, limite } = query;
    const [total, filas] = await Promise.all([
      this.prisma.palabra.count(),
      this.prisma.palabra.findMany({
        orderBy: { id: 'asc' },
        skip: (pagina - 1) * limite,
        take: limite,
        select: SELECT_ADMIN,
      }),
    ]);

    return {
      palabras: filas.map(aRespuestaAdmin),
      total,
      pagina,
      limite,
      total_paginas: Math.max(1, Math.ceil(total / limite)),
    };
  }

  // RF-08: solo texto + id_nivel son obligatorios; el resto puede llegar
  // después vía PATCH (RF-09) — T-022 recalcula completa solo cuando los 3
  // campos de contenido queden llenos.
  async crear(dto: CrearPalabraDto, idProfesorAutor: number) {
    await this.asegurarNivelExiste(dto.id_nivel);

    const creada = await this.prisma.palabra.create({
      data: {
        texto: dto.texto,
        idNivel: dto.id_nivel,
        significadoEs: dto.significado_es,
        oracionEjemplo: dto.oracion_ejemplo,
        idProfesorAutor,
      },
    });

    // No se confía en el valor de retorno de create() para "completa": el
    // trigger de T-022 corre después y RETURNING no lo ve en la misma
    // sentencia (ver nota en schema.prisma). Se relee la fila ya escrita.
    return this.obtenerParaAdmin(creada.id);
  }

  // RF-09: cualquier profesor edita cualquier campo de cualquier palabra
  // existente (catálogo compartido, sin propiedad individual). PATCH
  // parcial: solo se tocan los campos presentes en el body.
  async editar(idParam: string, dto: EditarPalabraDto) {
    const id = this.validarId(idParam);
    await this.asegurarPalabraExiste(id);
    if (dto.id_nivel !== undefined) {
      await this.asegurarNivelExiste(dto.id_nivel);
    }

    await this.prisma.palabra.update({
      where: { id },
      data: {
        texto: dto.texto,
        idNivel: dto.id_nivel,
        significadoEs: dto.significado_es,
        oracionEjemplo: dto.oracion_ejemplo,
      },
    });

    return this.obtenerParaAdmin(id);
  }

  // RF-10: reversible, no borra nada ni toca ningún otro campo.
  async ocultar(idParam: string, dto: OcultarPalabraDto) {
    const id = this.validarId(idParam);
    await this.asegurarPalabraExiste(id);

    await this.prisma.palabra.update({
      where: { id },
      data: { oculta: dto.oculta },
    });

    return this.obtenerParaAdmin(id);
  }

  private validarId(idParam: string): number {
    const id = parsearIdDeRuta(idParam);
    if (id === null) {
      throw errorPalabraIdInvalido();
    }
    return id;
  }

  private async asegurarPalabraExiste(id: number): Promise<void> {
    const palabra = await this.prisma.palabra.findUnique({ where: { id } });
    if (!palabra) {
      throw errorPalabraNoEncontrada();
    }
  }

  private async asegurarNivelExiste(idNivel: number): Promise<void> {
    const nivel = await this.prisma.nivel.findUnique({ where: { id: idNivel } });
    if (!nivel) {
      throw errorNivelNoEncontrado();
    }
  }

  private async obtenerParaAdmin(id: number) {
    const fila = await this.prisma.palabra.findUniqueOrThrow({
      where: { id },
      select: SELECT_ADMIN,
    });
    return aRespuestaAdmin(fila);
  }
}

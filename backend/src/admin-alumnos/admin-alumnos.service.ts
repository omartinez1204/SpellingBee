import { Injectable } from '@nestjs/common';
import { PaginacionDto } from '../common/dto/paginacion.dto.js';
import { PrismaService } from '../prisma/prisma.service.js';

type FilaPerfil = {
  idUsuario: number;
  nombre: string;
  apellidoPaterno: string;
  apellidoMaterno: string;
  carrera: string;
  semestre: number;
  usuario: { nombreUsuario: string };
};

@Injectable()
export class AdminAlumnosService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-28: TODOS los alumnos registrados (sin segmentación por grupo/curso,
  // confirmado en el ERS), con su avance general — cuántas palabras
  // DISTINTAS de cada nivel ha practicado cada uno. Paginado (RNF-12): nunca
  // trae más de "limite" (tope 50) alumnos en una sola consulta.
  //
  // Se parte de PerfilAlumno, no de Usuario filtrado por rol='alumno': la
  // relación PerfilAlumno.usuario es NO nula en el esquema (a diferencia de
  // Usuario.perfilAlumno, que sí lo es porque un profesor no tiene fila
  // aquí), así que partir de aquí evita tener que validar a mano un caso
  // que el propio esquema ya garantiza que no existe (todo alumno tiene
  // exactamente un perfil).
  async listar(query: PaginacionDto) {
    const { pagina, limite } = query;

    const [total, perfiles, niveles] = await Promise.all([
      this.prisma.perfilAlumno.count(),
      this.prisma.perfilAlumno.findMany({
        orderBy: { idUsuario: 'asc' },
        skip: (pagina - 1) * limite,
        take: limite,
        select: {
          idUsuario: true,
          nombre: true,
          apellidoPaterno: true,
          apellidoMaterno: true,
          carrera: true,
          semestre: true,
          usuario: { select: { nombreUsuario: true } },
        },
      }),
      this.prisma.nivel.findMany({
        orderBy: { orden: 'asc' },
        select: { id: true },
      }),
    ]);

    const conteos = await this.contarPalabrasDistintasPorNivel(
      perfiles.map((p) => p.idUsuario),
    );

    return {
      alumnos: perfiles.map((p) => this.aRespuestaAlumno(p, niveles, conteos)),
      total,
      pagina,
      limite,
      total_paginas: Math.max(1, Math.ceil(total / limite)),
    };
  }

  // idNivelEnPractica es la copia (RF-09) del nivel de la palabra AL MOMENTO
  // de practicarla, no una referencia viva — si el profesor mueve la
  // palabra a otro nivel después, el avance ya mostrado a un alumno no debe
  // saltar de nivel con ella (mismo criterio ya aplicado en RachaService/
  // InsigniasService). "Ha practicado" cuenta palabras DISTINTAS: practicar
  // la misma palabra varias veces no debe inflar el conteo.
  private async contarPalabrasDistintasPorNivel(idsAlumnos: number[]) {
    const conteos = new Map<string, number>();
    if (idsAlumnos.length === 0) return conteos;

    const filas = await this.prisma.registroPractica.findMany({
      where: { idAlumno: { in: idsAlumnos } },
      select: { idAlumno: true, idNivelEnPractica: true, idPalabra: true },
      distinct: ['idAlumno', 'idNivelEnPractica', 'idPalabra'],
    });

    for (const fila of filas) {
      const clave = `${fila.idAlumno}:${fila.idNivelEnPractica}`;
      conteos.set(clave, (conteos.get(clave) ?? 0) + 1);
    }
    return conteos;
  }

  private aRespuestaAlumno(
    perfil: FilaPerfil,
    niveles: { id: number }[],
    conteos: Map<string, number>,
  ) {
    return {
      id: perfil.idUsuario,
      matricula: perfil.usuario.nombreUsuario,
      nombre: perfil.nombre,
      apellido_paterno: perfil.apellidoPaterno,
      apellido_materno: perfil.apellidoMaterno,
      carrera: perfil.carrera,
      semestre: perfil.semestre,
      // Los 3 niveles siempre aparecen, incluso en 0 — un alumno que nunca
      // practicó no desaparece de esta lista ni de su propio arreglo de
      // avance (RF-28 pide verlo por cada alumno REGISTRADO, no solo por
      // los que ya tienen actividad).
      avance: niveles.map((nivel) => ({
        id_nivel: nivel.id,
        palabras_practicadas:
          conteos.get(`${perfil.idUsuario}:${nivel.id}`) ?? 0,
      })),
    };
  }
}

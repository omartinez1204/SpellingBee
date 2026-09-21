import { HttpStatus, Injectable } from '@nestjs/common';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { FiltrosAlumnosDto } from './dto/filtros-alumnos.dto.js';

type FilaPerfil = {
  idUsuario: number;
  nombre: string;
  apellidoPaterno: string;
  apellidoMaterno: string;
  carrera: string;
  semestre: number;
  usuario: { nombreUsuario: string };
};

function errorAlumnoIdInvalido(): DominioException {
  return new DominioException(
    'ALUMNO_ID_INVALIDO',
    'El id de alumno debe ser un número entero positivo.',
    HttpStatus.BAD_REQUEST,
  );
}

function errorAlumnoNoEncontrado(): DominioException {
  return new DominioException(
    'ALUMNO_NO_ENCONTRADO',
    'No existe un alumno con ese id.',
    HttpStatus.NOT_FOUND,
  );
}

@Injectable()
export class AdminAlumnosService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-28, RF-30: TODOS los alumnos registrados que cumplan simultáneamente
  // los filtros opcionales de carrera/semestre (sin segmentación por
  // grupo/curso, confirmado en el ERS), con su avance general — cuántas
  // palabras DISTINTAS de cada nivel ha practicado cada uno. Si además viene
  // un filtro de nivel, el arreglo de avance se ANGOSTA a solo ese nivel
  // (RF-30, ejemplo del ERS: "...con su avance en el Nivel 2") — no excluye
  // alumnos por su conteo en ese nivel, solo reduce qué niveles se muestran
  // [decisión de equipo: el ERS no dice si un nivel sin actividad debería
  // excluir al alumno; se optó por seguir mostrándolo, igual que ya se hace
  // sin filtros, para no ocultar a quien "todavía no empieza" ese nivel].
  // Paginado (RNF-12): nunca trae más de "limite" (tope 50) alumnos en una
  // sola consulta.
  //
  // Se parte de PerfilAlumno, no de Usuario filtrado por rol='alumno': la
  // relación PerfilAlumno.usuario es NO nula en el esquema (a diferencia de
  // Usuario.perfilAlumno, que sí lo es porque un profesor no tiene fila
  // aquí), así que partir de aquí evita tener que validar a mano un caso
  // que el propio esquema ya garantiza que no existe (todo alumno tiene
  // exactamente un perfil).
  async listar(query: FiltrosAlumnosDto) {
    const { pagina, limite, nivel, carrera, semestre } = query;

    const wherePerfil = {
      ...(carrera !== undefined && { carrera }),
      ...(semestre !== undefined && { semestre }),
    };

    const [total, perfiles, niveles] = await Promise.all([
      this.prisma.perfilAlumno.count({ where: wherePerfil }),
      this.prisma.perfilAlumno.findMany({
        where: wherePerfil,
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
        where: nivel !== undefined ? { id: nivel } : undefined,
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

  // RF-29, RF-30: detalle de UN alumno — palabra, tiempo y oración de CADA
  // intento (a diferencia de RF-28/listar(), aquí no se deduplica por
  // palabra: si practicó la misma palabra 3 veces, son 3 filas, una por
  // intento real). A propósito NO incluye deletreo_correcto: el propio ERS
  // enumera solo "tiempo empleado y oración escrita" para esta tabla, a
  // diferencia de la lista más completa de campos que sí guarda
  // RegistroPractica (RF-27). Paginado (RNF-12), igual que listar().
  //
  // Filtros (RF-30): nivel angosta los INTENTOS mostrados a los practicados
  // en ese nivel (idNivelEnPractica). carrera/semestre son atributos del
  // propio alumno, no de cada intento — como :id ya fija de cuál alumno se
  // trata, si ese alumno no cumple el filtro el resultado es una lista
  // vacía (existe, solo no pasa el filtro), nunca un 404: eso queda
  // reservado para un id que de plano no corresponde a ningún alumno.
  async detalle(idAlumnoParam: string, query: FiltrosAlumnosDto) {
    const idAlumno = parsearIdDeRuta(idAlumnoParam);
    if (idAlumno === null) {
      throw errorAlumnoIdInvalido();
    }

    const perfil = await this.prisma.perfilAlumno.findUnique({
      where: { idUsuario: idAlumno },
    });
    if (!perfil) {
      throw errorAlumnoNoEncontrado();
    }

    const { pagina, limite, nivel, carrera, semestre } = query;

    const cumpleFiltroDeAlumno =
      (carrera === undefined || perfil.carrera === carrera) &&
      (semestre === undefined || perfil.semestre === semestre);

    const whereRegistros = {
      idAlumno,
      ...(nivel !== undefined && { idNivelEnPractica: nivel }),
    };

    const [total, registros] = cumpleFiltroDeAlumno
      ? await Promise.all([
          this.prisma.registroPractica.count({ where: whereRegistros }),
          this.prisma.registroPractica.findMany({
            where: whereRegistros,
            // Más reciente primero: para revisar el progreso de un alumno,
            // lo último que hizo es lo más relevante [decisión de equipo —
            // el ERS no fija el orden]. `id` desc desempata (T-070):
            // fecha_hora no es única — dos registros pueden coincidir al
            // milisegundo — y sin un segundo criterio único el motor puede
            // ordenar los empatados distinto en cada consulta, de modo que
            // skip/take repetiría u omitiría uno entre páginas.
            orderBy: [{ fechaHora: 'desc' }, { id: 'desc' }],
            skip: (pagina - 1) * limite,
            take: limite,
            select: {
              tiempoSegundos: true,
              oracionAlumno: true,
              palabra: { select: { id: true, texto: true } },
            },
          }),
        ])
      : ([0, []] as const);

    return {
      intentos: registros.map((r) => ({
        id_palabra: r.palabra.id,
        palabra: r.palabra.texto,
        tiempo_segundos: r.tiempoSegundos,
        oracion_alumno: r.oracionAlumno,
      })),
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
      // Los niveles presentes aquí ya vienen decididos por listar() — todos
      // (sin filtro) o solo el filtrado (RF-30) — y, dentro de esos, un
      // alumno que nunca practicó no desaparece ni queda fuera del arreglo
      // (RF-28 pide verlo por cada alumno REGISTRADO, no solo por los que ya
      // tienen actividad).
      avance: niveles.map((nivel) => ({
        id_nivel: nivel.id,
        palabras_practicadas:
          conteos.get(`${perfil.idUsuario}:${nivel.id}`) ?? 0,
      })),
    };
  }
}

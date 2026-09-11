import { Injectable } from '@nestjs/common';
import { Prisma } from '../generated/prisma/client.js';
import { PrismaService } from '../prisma/prisma.service.js';

// Forma que espera el cliente para el mensaje emergente de felicitación
// (RF-24, punto 1) — null cuando este intento de práctica NO otorgó una
// insignia nueva (ni completó nada, ni ya la tenía de antes).
export interface InsigniaOtorgada {
  id_nivel: number;
  nombre_nivel: string;
  fecha_otorgada: Date;
}

// Cliente Prisma "normal" o el proxy de $transaction — igual que
// RachaService (T-046): evaluarAlPracticar() debe correr DENTRO de la misma
// transacción que crea el RegistroPractica, para que el intento recién
// guardado ya cuente al decidir si el nivel quedó completo.
type ClientePrisma = PrismaService | Prisma.TransactionClient;

@Injectable()
export class InsigniasService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-24 / CU-01 paso 9. Se llama como efecto de guardar un intento de
  // práctica (PracticaService.guardarPractica) — nunca por su cuenta, igual
  // que la racha. Permanente: si el alumno YA tiene la insignia de este
  // nivel, no se vuelve a evaluar ni se revoca por ningún motivo (ver la
  // nota de RF-09 en el ERS sobre cambios de nivel/contenido posteriores).
  async evaluarAlPracticar(
    idAlumno: number,
    idNivel: number,
    cliente: ClientePrisma = this.prisma,
  ): Promise<InsigniaOtorgada | null> {
    const yaExiste = await cliente.insignia.findUnique({
      where: { idAlumno_idNivel: { idAlumno, idNivel } },
    });
    if (yaExiste) {
      return null;
    }

    // "Palabras completas de un nivel" (RF-24) es literalmente el mismo
    // conjunto que ve el alumno para practicar (RF-06): completa=true Y
    // oculta=false — ver NivelesService.listarPalabras. Si todavía no hay
    // ninguna palabra completa en este nivel, 0/0 no cuenta como "100%": no
    // hay nada que completar aún (mismo criterio que RF-06, donde una lista
    // vacía es un resultado válido, no un caso especial de "ya terminado").
    const palabrasDelNivel = await cliente.palabra.findMany({
      where: { idNivel, completa: true, oculta: false },
      select: { id: true },
    });
    if (palabrasDelNivel.length === 0) {
      return null;
    }

    const idsPalabras = palabrasDelNivel.map((p) => p.id);
    const practicadas = await cliente.registroPractica.findMany({
      where: { idAlumno, idPalabra: { in: idsPalabras } },
      select: { idPalabra: true },
      distinct: ['idPalabra'],
    });
    if (practicadas.length < idsPalabras.length) {
      return null;
    }

    const nivel = await cliente.nivel.findUniqueOrThrow({
      where: { id: idNivel },
      select: { nombre: true },
    });
    const insignia = await cliente.insignia.create({
      data: { idAlumno, idNivel },
    });

    return {
      id_nivel: idNivel,
      nombre_nivel: nivel.nombre,
      fecha_otorgada: insignia.fechaOtorgada,
    };
  }

  // RF-24, punto 2: insignias ya obtenidas por el alumno en sesión, para la
  // pantalla de perfil/progreso. Devuelve solo las YA GANADAS (no una lista
  // de los 3 niveles con un flag ganada/no-ganada) [decisión de equipo, a
  // confirmar]: GET /niveles ya expone los 3 niveles posibles si Flutter
  // quiere mostrar también los "espacios" de insignias no ganadas todavía.
  async obtenerInsigniasDeAlumno(idAlumno: number): Promise<InsigniaOtorgada[]> {
    const insignias = await this.prisma.insignia.findMany({
      where: { idAlumno },
      include: { nivel: { select: { nombre: true } } },
      orderBy: { nivel: { orden: 'asc' } },
    });

    return insignias.map((i) => ({
      id_nivel: i.idNivel,
      nombre_nivel: i.nivel.nombre,
      fecha_otorgada: i.fechaOtorgada,
    }));
  }
}

import { Injectable } from '@nestjs/common';
import {
  errorPalabraIdInvalido,
  errorPalabraNoEncontrada,
} from '../palabras/palabras.service.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { InsigniasService } from '../insignias/insignias.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { RachaService } from '../racha/racha.service.js';
import { GuardarPracticaDto } from './dto/guardar-practica.dto.js';

@Injectable()
export class PracticaService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rachaService: RachaService,
    private readonly insigniasService: InsigniasService,
  ) {}

  // RF-22 (T-042). "Mejor tiempo" = el más BAJO entre los intentos previos
  // del propio alumno para esa palabra (el cronómetro mide qué tan rápido
  // termina, T-040/T-041 — menos tiempo es mejor). No filtra por
  // `sincronizado`: un registro ya escrito localmente cuenta como intento
  // real aunque todavía no haya llegado al servidor (RF-33 es sobre
  // entrega, no sobre si el intento "cuenta").
  //
  // IMPORTANTE al llamar esto junto con guardarPractica() (T-045) para el
  // mismo intento: este método debe consultarse ANTES de guardar el intento
  // actual, nunca después — si el registro de hoy ya estuviera guardado, el
  // MIN lo incluiría a él mismo y "mejor tiempo previo" dejaría de ser
  // "previo". La pantalla de Flutter respeta ese orden (ver
  // practica_palabra_screen.dart, _terminarPractica()).
  async obtenerMejorTiempo(idAlumno: number, idPalabraParam: string) {
    const idPalabra = parsearIdDeRuta(idPalabraParam);
    if (idPalabra === null) {
      throw errorPalabraIdInvalido();
    }

    const resultado = await this.prisma.registroPractica.aggregate({
      where: { idAlumno, idPalabra },
      _min: { tiempoSegundos: true },
    });

    return { mejor_tiempo_segundos: resultado._min.tiempoSegundos };
  }

  // T-045/T-046/T-047 (RF-21, RF-23, RF-24, RF-27). Guarda el intento y,
  // como efecto del mismo guardado (CU-01, pasos 9 del ERS), actualiza la
  // racha de días consecutivos y evalúa si este intento completó el 100%
  // de las palabras completas del nivel — las tres escrituras van en una
  // sola transacción: si cualquiera fallara, no debe quedar un
  // RegistroPractica sin su racha/insignia actualizada ni viceversa.
  // Tampoco vuelve a evaluar deletreo_correcto ni oracion_alumno contra la
  // palabra: RF-25/RF-26 ya se verifican en el cliente (T-043/T-044) y
  // RF-26 es explícito en que esa verificación "no bloquea el guardado" —
  // re-hacerla aquí solo para no actuar sobre el resultado sería ceremonia
  // sin efecto.
  async guardarPractica(idAlumno: number, dto: GuardarPracticaDto) {
    const palabra = await this.prisma.palabra.findUnique({
      where: { id: dto.id_palabra },
      select: { idNivel: true },
    });
    if (!palabra) {
      throw errorPalabraNoEncontrada();
    }

    const { idRegistro, insigniaOtorgada } = await this.prisma.$transaction(
      async (tx) => {
        const registro = await tx.registroPractica.create({
          data: {
            idAlumno,
            idPalabra: dto.id_palabra,
            // Snapshot (RF-09): copia del valor de HOY, no una relación viva
            // — si el profesor cambia el nivel de la palabra después, este
            // registro ya guardado no debe moverse con él.
            idNivelEnPractica: palabra.idNivel,
            tiempoSegundos: dto.tiempo_segundos,
            oracionAlumno: dto.oracion_alumno,
            deletreoCorrecto: dto.deletreo_correcto,
            // Se crea directo en el servidor (el alumno tiene conexión en
            // este momento) — no es un registro pendiente de la cola offline
            // (RF-33, T-062/T-063, todavía no existe), así que ya está
            // sincronizado por definición.
            sincronizado: true,
          },
          select: { id: true },
        });

        await this.rachaService.actualizarAlPracticar(
          idAlumno,
          dto.fecha_local,
          tx,
        );

        // Con el nivel de la palabra recién practicada (no de todos los
        // niveles): practicar una palabra de un nivel solo puede completar
        // ESE nivel, nunca otro.
        const insigniaOtorgada = await this.insigniasService.evaluarAlPracticar(
          idAlumno,
          palabra.idNivel,
          tx,
        );

        return { idRegistro: registro.id, insigniaOtorgada };
      },
    );

    return { id: idRegistro, insignia_otorgada: insigniaOtorgada };
  }
}

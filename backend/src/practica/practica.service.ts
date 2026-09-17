import { Injectable } from '@nestjs/common';
import {
  errorPalabraIdInvalido,
  errorPalabraNoEncontrada,
} from '../palabras/palabras.service.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { Prisma } from '../generated/prisma/client.js';
import { InsigniaOtorgada, InsigniasService } from '../insignias/insignias.service.js';
import { PrismaService } from '../prisma/prisma.service.js';
import { RachaService } from '../racha/racha.service.js';
import { GuardarPracticaDto } from './dto/guardar-practica.dto.js';
import { SincronizarPracticaDto } from './dto/sincronizar-practica.dto.js';

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
    const { idRegistro, insigniaOtorgada } = await this.prisma.$transaction(
      (tx) =>
        this.crearRegistroPractica(tx, idAlumno, {
          idPalabra: dto.id_palabra,
          tiempoSegundos: dto.tiempo_segundos,
          oracionAlumno: dto.oracion_alumno,
          deletreoCorrecto: dto.deletreo_correcto,
          fechaLocal: dto.fecha_local,
        }),
    );

    return { id: idRegistro, insignia_otorgada: insigniaOtorgada };
  }

  // T-063 (RF-33): recepción en LOTE de la cola offline de Flutter (T-062,
  // SincronizadorPractica). Idempotente por registro: `id` lo genera el
  // CLIENTE (docs/diseno-tecnico.md §3.6), así que un reintento que reenvía
  // un lote donde algunos registros YA se habían recibido en un intento
  // anterior simplemente los salta — nunca los duplica ni los sobreescribe.
  //
  // TODO EL LOTE en una sola transacción (a diferencia de una transacción
  // por registro): si un registro fallara a medio lote (p. ej. una
  // id_palabra que ya no existe — algo que hoy no debería poder pasar,
  // ninguna pantalla de administración borra palabras, solo las oculta,
  // T-024), es preferible que el lote COMPLETO se reintente entero la
  // próxima vez (todo-o-nada) a dejar una sincronización a medias: el
  // cliente (SincronizadorPractica.intentarSincronizar()) solo vacía su
  // cola local cuando esta llamada resuelve con éxito completo.
  async sincronizarLote(idAlumno: number, dto: SincronizarPracticaDto) {
    // RF-33: se procesa por fecha_local ASCENDENTE, no en el orden en que
    // llegó el arreglo. RachaService.actualizarAlPracticar compara cada
    // fecha contra la ÚLTIMA ya registrada y descarta silenciosamente
    // cualquiera "anterior" a esa (postura defensiva ante un reloj que
    // retrocede, ver ese archivo) — si un lote trajera, por ejemplo, el
    // intento del día 3 antes que el del día 1, procesar en el orden
    // recibido perdería el día 1 para efectos de la racha. Ordenar aquí
    // garantiza que sincronizar un lote offline produzca la MISMA racha
    // final que si cada intento se hubiera enviado el mismo día en que
    // ocurrió.
    const registrosOrdenados = [...dto.registros].sort((a, b) =>
      a.fecha_local.localeCompare(b.fecha_local),
    );

    let sincronizados = 0;
    let yaExistian = 0;

    await this.prisma.$transaction(async (tx) => {
      for (const registro of registrosOrdenados) {
        const existente = await tx.registroPractica.findUnique({
          where: { idCliente: registro.id },
          select: { id: true },
        });
        if (existente) {
          yaExistian++;
          continue;
        }

        await this.crearRegistroPractica(tx, idAlumno, {
          idPalabra: registro.id_palabra,
          tiempoSegundos: registro.tiempo_segundos,
          oracionAlumno: registro.oracion_alumno,
          deletreoCorrecto: registro.deletreo_correcto,
          fechaLocal: registro.fecha_local,
          idCliente: registro.id,
        });
        sincronizados++;
      }
    });

    return { sincronizados, ya_existian: yaExistian };
  }

  // Compartido por guardarPractica() (T-045) y sincronizarLote() (T-063):
  // crear el RegistroPractica y, como su mismo efecto, actualizar racha
  // (RF-23) y evaluar insignia (RF-24) — siempre dentro de la transacción
  // de quien llama (`tx`), nunca por separado, para que las tres escrituras
  // vivan o mueran juntas. `idCliente` es opcional porque el camino en
  // línea de siempre (T-045) no manda ninguno (ver nota del campo en
  // schema.prisma).
  private async crearRegistroPractica(
    tx: Prisma.TransactionClient,
    idAlumno: number,
    datos: {
      idPalabra: number;
      tiempoSegundos: number;
      oracionAlumno: string;
      deletreoCorrecto: boolean;
      fechaLocal: string;
      idCliente?: string;
    },
  ): Promise<{ idRegistro: number; insigniaOtorgada: InsigniaOtorgada | null }> {
    const palabra = await tx.palabra.findUnique({
      where: { id: datos.idPalabra },
      select: { idNivel: true },
    });
    if (!palabra) {
      throw errorPalabraNoEncontrada();
    }

    const registro = await tx.registroPractica.create({
      data: {
        idAlumno,
        idPalabra: datos.idPalabra,
        // Snapshot (RF-09): copia del valor de HOY, no una relación viva —
        // si el profesor cambia el nivel de la palabra después, este
        // registro ya guardado no debe moverse con él.
        idNivelEnPractica: palabra.idNivel,
        tiempoSegundos: datos.tiempoSegundos,
        oracionAlumno: datos.oracionAlumno,
        deletreoCorrecto: datos.deletreoCorrecto,
        idCliente: datos.idCliente,
        // Por ambos caminos (en línea o sincronizado después) el registro
        // YA está en el servidor en el momento en que esta función corre —
        // la diferencia entre los dos (RF-33) es CUÁNDO llegó, no si quedó
        // sincronizado.
        sincronizado: true,
      },
      select: { id: true },
    });

    await this.rachaService.actualizarAlPracticar(idAlumno, datos.fechaLocal, tx);

    // Con el nivel de la palabra recién practicada (no de todos los
    // niveles): practicar una palabra de un nivel solo puede completar ESE
    // nivel, nunca otro.
    const insigniaOtorgada = await this.insigniasService.evaluarAlPracticar(
      idAlumno,
      palabra.idNivel,
      tx,
    );

    return { idRegistro: registro.id, insigniaOtorgada };
  }
}

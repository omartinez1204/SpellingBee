import { HttpStatus, Injectable } from '@nestjs/common';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import {
  diferenciaEnDias,
  parsearFechaLocal,
} from '../common/fecha-local.util.js';
import { Prisma } from '../generated/prisma/client.js';
import { PrismaService } from '../prisma/prisma.service.js';

export function errorFechaLocalInvalida(): DominioException {
  return new DominioException(
    'FECHA_LOCAL_INVALIDA',
    'fecha_local debe ser una fecha real en formato YYYY-MM-DD.',
    HttpStatus.BAD_REQUEST,
  );
}

// Cliente Prisma "normal" o el proxy que entrega $transaction(async tx =>
// ...) — actualizarAlPracticar() necesita poder correr DENTRO de la misma
// transacción que crea el RegistroPractica (PracticaService), sin forzar
// una escritura de Racha aparte que pudiera quedar huérfana si el resto
// del guardado fallara.
type ClientePrisma = PrismaService | Prisma.TransactionClient;

@Injectable()
export class RachaService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-23. Se llama como efecto de guardar un intento de práctica
  // (PracticaService.guardarPractica, T-045/T-046) — nunca por su cuenta:
  // no hay una acción de alumno que "solo actualice la racha" sin
  // practicar. `cliente` permite pasar el `tx` de una transacción en curso;
  // por defecto usa la conexión normal para quien llame esto fuera de una.
  async actualizarAlPracticar(
    idAlumno: number,
    fechaLocalStr: string,
    cliente: ClientePrisma = this.prisma,
  ): Promise<void> {
    const fechaLocal = parsearFechaLocal(fechaLocalStr);
    if (!fechaLocal) {
      throw errorFechaLocalInvalida();
    }

    const actual = await cliente.racha.findUnique({ where: { idAlumno } });

    if (!actual) {
      // Primer intento de práctica de este alumno en toda la app: hoy es
      // el día 1 de la racha, no hay "anterior" contra qué comparar.
      await cliente.racha.create({
        data: { idAlumno, diasConsecutivos: 1, ultimaFechaPractica: fechaLocal },
      });
      return;
    }

    const diferencia = diferenciaEnDias(actual.ultimaFechaPractica, fechaLocal);

    if (diferencia === 0) {
      // Mismo día calendario local que el último registro: ya contaba
      // desde el intento anterior de hoy — RF-23 exige un día "distinto",
      // así que practicar de nuevo hoy ni suma ni resta.
      return;
    }

    if (diferencia < 0) {
      // La fecha local que manda el cliente es ANTERIOR a la última ya
      // registrada. El reloj de un dispositivo real no debería retroceder,
      // y el ERS no define qué hacer si pasa (reloj manipulado, error del
      // cliente, etc.) — postura defensiva: no tocar la racha ya guardada
      // en vez de arriesgarse a corromperla con una fecha no confiable.
      return;
    }

    const nuevosDiasConsecutivos =
      diferencia === 1
        ? actual.diasConsecutivos + 1 // día siguiente consecutivo: sube.
        : 1; // se saltó al menos un día completo: la racha anterior se
    // rompió: HOY es el día 1 de una racha nueva, no queda en 0 después de
    // este intento (0 solo describe el estado ANTES de volver a practicar).

    await cliente.racha.update({
      where: { idAlumno },
      data: {
        diasConsecutivos: nuevosDiasConsecutivos,
        ultimaFechaPractica: fechaLocal,
      },
    });
  }

  // RF-23. Lectura EN VIVO, no solo el valor crudo guardado: "se reinicia a
  // 0 si transcurre un día calendario local completo sin ningún registro"
  // describe un estado que puede volverse cierto sin que el alumno haga
  // nada — si ya pasó un día completo desde el último registro, se debe
  // MOSTRAR 0 aunque la fila en la base todavía diga el valor viejo (ese
  // valor solo se corrige de verdad la próxima vez que el alumno practique
  // y dispare actualizarAlPracticar). Esta lectura NUNCA escribe.
  async obtenerRachaActual(idAlumno: number, fechaLocalHoyStr: string) {
    const fechaLocalHoy = parsearFechaLocal(fechaLocalHoyStr);
    if (!fechaLocalHoy) {
      throw errorFechaLocalInvalida();
    }

    const actual = await this.prisma.racha.findUnique({ where: { idAlumno } });
    if (!actual) {
      return { dias_consecutivos: 0 };
    }

    const diferencia = diferenciaEnDias(actual.ultimaFechaPractica, fechaLocalHoy);
    // diferencia <= 0: practicó hoy, o la fecha "de hoy" es rara (ver nota
    // de reloj retrocedido arriba) — se muestra el valor guardado.
    // diferencia === 1: ayer fue el último registro; hoy todavía no ha
    // "transcurrido completo" sin práctica (el propio día de hoy es la
    // oportunidad de mantenerla viva), así que la racha sigue mostrándose.
    // diferencia >= 2: al menos un día calendario completo pasó de largo
    // sin ningún registro — la racha ya está rota, aunque el alumno
    // todavía no vuelva a practicar para que quede escrito así.
    const diasConsecutivos = diferencia <= 1 ? actual.diasConsecutivos : 0;

    return { dias_consecutivos: diasConsecutivos };
  }
}

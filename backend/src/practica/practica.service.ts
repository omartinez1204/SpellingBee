import { Injectable } from '@nestjs/common';
import { errorPalabraIdInvalido } from '../palabras/palabras.service.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { PrismaService } from '../prisma/prisma.service.js';

@Injectable()
export class PracticaService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-22 (T-042). "Mejor tiempo" = el más BAJO entre los intentos previos
  // del propio alumno para esa palabra (el cronómetro mide qué tan rápido
  // termina, T-040/T-041 — menos tiempo es mejor). No filtra por
  // `sincronizado`: un registro ya escrito localmente cuenta como intento
  // real aunque todavía no haya llegado al servidor (RF-33 es sobre
  // entrega, no sobre si el intento "cuenta").
  //
  // T-045 (POST /practica) todavía no existe, así que RegistroPractica no
  // tiene ninguna fila todavía — este método SIEMPRE regresa null por ahora.
  // Eso es correcto, no un caso especial: es la consulta real, aplicada a
  // una tabla que hoy está vacía.
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
}

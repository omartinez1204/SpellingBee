import { HttpStatus, Injectable } from '@nestjs/common';
import { DominioException } from '../common/exceptions/dominio.exception.js';
import { parsearIdDeRuta } from '../common/parsear-id-de-ruta.util.js';
import { PrismaService } from '../prisma/prisma.service.js';

function errorPalabraIdInvalido(): DominioException {
  return new DominioException(
    'PALABRA_ID_INVALIDO',
    'El id de palabra debe ser un número entero positivo.',
    HttpStatus.BAD_REQUEST,
  );
}

function errorPalabraNoEncontrada(): DominioException {
  return new DominioException(
    'PALABRA_NO_ENCONTRADA',
    'No existe una palabra con ese id.',
    HttpStatus.NOT_FOUND,
  );
}

// [decisión de equipo, a confirmar] Convención de URL pública de audio:
// diseno-tecnico.md solo pide "url de audio", no fija la ruta. Se usa
// /assets/audios/<archivo> porque es el mismo nombre de carpeta que
// RF-11/T-025 ya usan para guardar el archivo en disco — así T-025 solo
// tiene que servir esa carpeta como estática con ese prefijo, sin inventar
// un alias distinto. Es una ruta RELATIVA, no un URL absoluto: el cliente
// Flutter ya antepone su propio API_BASE_URL a cada ruta (ver
// app/lib/core/api_client.dart), y el backend no puede saber con qué
// host/puerto lo alcanza cada cliente (emulador, dispositivo físico o
// producción tienen valores distintos).
function urlAudio(nombreArchivoAudio: string | null): string | null {
  return nombreArchivoAudio ? `/assets/audios/${nombreArchivoAudio}` : null;
}

@Injectable()
export class PalabrasService {
  constructor(private readonly prisma: PrismaService) {}

  // RF-07: el detalle siempre trae los 4 campos, completos o no, sin ocultar
  // nada — decidir qué mostrar de entrada y qué revelar tras las pistas
  // ("Ver significado"/"Ver ejemplo") es responsabilidad de la app Flutter,
  // no de este endpoint.
  //
  // A propósito NO filtra por completa/oculta (a diferencia de
  // GET /niveles/:id/palabras, T-021): ni el ERS ni diseno-tecnico.md piden
  // ese filtro aquí, solo en el listado. En el flujo normal, la app llega a
  // este id a través de esa lista ya filtrada.
  async obtenerDetalle(idParam: string) {
    const id = parsearIdDeRuta(idParam);
    if (id === null) {
      throw errorPalabraIdInvalido();
    }

    const palabra = await this.prisma.palabra.findUnique({
      where: { id },
      select: {
        id: true,
        texto: true,
        significadoEs: true,
        oracionEjemplo: true,
        nombreArchivoAudio: true,
      },
    });
    if (!palabra) {
      throw errorPalabraNoEncontrada();
    }

    return {
      id: palabra.id,
      texto: palabra.texto,
      significado_es: palabra.significadoEs,
      oracion_ejemplo: palabra.oracionEjemplo,
      url_audio: urlAudio(palabra.nombreArchivoAudio),
    };
  }
}

import {
  type ArgumentsHost,
  Catch,
  type ExceptionFilter,
  PayloadTooLargeException,
} from '@nestjs/common';
import { HttpExceptionFilter } from '../common/filters/http-exception.filter.js';
import { errorAudioTamanoInvalido } from './admin-palabras.service.js';

// T-071 (RNF-01). Multer corta la subida en su límite CRUDO (5 MB, solo una
// red de seguridad contra un cliente abusivo) y Nest lo convierte en
// PayloadTooLargeException("File too large") — en inglés, y con otro código
// que el error de negocio. Para quien sube el audio es EL MISMO problema que
// pasarse de 1 MB (RF-11): se responde con exactamente el mismo error que
// AdminPalabrasService, sin repetir aquí su texto.
@Catch(PayloadTooLargeException)
export class ArchivoDemasiadoGrandeFilter implements ExceptionFilter {
  catch(_exception: PayloadTooLargeException, host: ArgumentsHost): void {
    new HttpExceptionFilter().catch(errorAudioTamanoInvalido(), host);
  }
}

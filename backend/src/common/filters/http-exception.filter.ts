import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Response } from 'express';
import {
  MENSAJE_ERROR_GENERICO,
  traducirErrorInterno,
  traducirMensajeDeValidacion,
} from './mensajes-en-espanol.js';

interface ErrorBody {
  code: string;
  message: string;
}

// Traduce cualquier excepción a la forma uniforme de docs/diseno-tecnico.md §3:
// { "error": { "code", "message" } }. DominioException ya trae su propio code;
// los errores de ValidationPipe (class-validator) y cualquier otro caso caen
// a un code genérico en vez de romper el contrato.
//
// T-071 (RNF-01): el message llega tal cual a la pantalla de la app Flutter,
// así que NUNCA sale texto en inglés de librerías (Nest, class-validator,
// multer, body-parser): ver ./mensajes-en-espanol.ts.
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      response
        .status(exception.getStatus())
        .json({ error: this.desdeHttpException(exception) });
      return;
    }

    this.logger.error(exception);
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      error: {
        code: 'ERROR_INTERNO',
        message: MENSAJE_ERROR_GENERICO,
      },
    });
  }

  private desdeHttpException(exception: HttpException): ErrorBody {
    const body = exception.getResponse();
    const estado = exception.getStatus();

    if (typeof body === 'object' && body !== null) {
      const b = body as Record<string, unknown>;
      // DominioException: ya trae code y message propios, en español.
      if (typeof b.code === 'string' && typeof b.message === 'string') {
        return { code: b.code, message: b.message };
      }
      if ('message' in b) {
        // ValidationPipe: un arreglo con un mensaje por cada regla rota. Los
        // de nuestros DTO ya están en español; los que genera class-validator
        // por su cuenta se traducen fragmento a fragmento.
        if (Array.isArray(b.message)) {
          return {
            code: 'VALIDACION',
            message: b.message
              .map((m) => traducirMensajeDeValidacion(String(m)))
              .join('; '),
          };
        }
        // Mensaje suelto (Nest, multer, body-parser): casi seguro en inglés.
        return traducirErrorInterno(estado, String(b.message));
      }
    }

    return traducirErrorInterno(estado, typeof body === 'string' ? body : '');
  }
}

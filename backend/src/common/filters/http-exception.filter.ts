import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Response } from 'express';

interface ErrorBody {
  code: string;
  message: string;
}

// Traduce cualquier excepción a la forma uniforme de docs/diseno-tecnico.md §3:
// { "error": { "code", "message" } }. DominioException ya trae su propio code;
// los errores de ValidationPipe (class-validator) y cualquier otro caso caen
// a un code genérico en vez de romper el contrato.
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
        message: 'Ocurrió un error inesperado. Intenta de nuevo más tarde.',
      },
    });
  }

  private desdeHttpException(exception: HttpException): ErrorBody {
    const body = exception.getResponse();

    if (typeof body === 'object' && body !== null) {
      const b = body as Record<string, unknown>;
      if (typeof b.code === 'string' && typeof b.message === 'string') {
        return { code: b.code, message: b.message };
      }
      if ('message' in b) {
        const message = Array.isArray(b.message)
          ? b.message.join('; ')
          : String(b.message);
        return { code: 'VALIDACION', message };
      }
    }

    return {
      code: 'ERROR',
      message: typeof body === 'string' ? body : 'Ocurrió un error.',
    };
  }
}

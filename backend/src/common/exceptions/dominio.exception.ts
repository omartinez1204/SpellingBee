import { HttpException, HttpStatus } from '@nestjs/common';

// Error de negocio con código estable para el contrato uniforme del API
// (docs/diseno-tecnico.md §3): { "error": { "code", "message" } }.
export class DominioException extends HttpException {
  constructor(
    code: string,
    message: string,
    status: HttpStatus = HttpStatus.BAD_REQUEST,
  ) {
    super({ code, message }, status);
  }
}

import {
  PayloadTooLargeException,
  type ArgumentsHost,
} from '@nestjs/common';
import { describe, expect, it, vi } from 'vitest';
import { ArchivoDemasiadoGrandeFilter } from './archivo-demasiado-grande.filter.js';

// T-071 (RNF-01): el límite crudo de multer (5 MB) llega como
// PayloadTooLargeException("File too large") — en inglés. Debe responder con
// EL MISMO error de negocio que pasarse de 1 MB (RF-11).
describe('ArchivoDemasiadoGrandeFilter', () => {
  it('responde con el error de negocio de 1 MB en español, no con "File too large"', () => {
    const res = { status: vi.fn().mockReturnThis(), json: vi.fn() };
    const host = {
      switchToHttp: () => ({ getResponse: () => res }),
    } as unknown as ArgumentsHost;

    new ArchivoDemasiadoGrandeFilter().catch(
      new PayloadTooLargeException('File too large'),
      host,
    );

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      error: {
        code: 'AUDIO_TAMANO_INVALIDO',
        message: 'El archivo no puede pesar más de 1 MB.',
      },
    });
  });
});

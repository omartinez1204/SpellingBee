import {
  BadRequestException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Logger,
  NotFoundException,
  PayloadTooLargeException,
  UnauthorizedException,
  type ArgumentsHost,
} from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DominioException } from '../exceptions/dominio.exception.js';
import { HttpExceptionFilter } from './http-exception.filter.js';

// T-071 (RNF-01): el filtro es lo último que toca un error antes de llegar a
// la pantalla de la app (ApiException.message se muestra tal cual). Nest,
// class-validator, multer y body-parser generan mensajes en INGLÉS; aquí se
// comprueba que ninguno llega así.

function responder(excepcion: unknown) {
  const res = { status: vi.fn().mockReturnThis(), json: vi.fn() };
  const host = {
    switchToHttp: () => ({ getResponse: () => res }),
  } as unknown as ArgumentsHost;
  new HttpExceptionFilter().catch(excepcion, host);
  const [[status]] = res.status.mock.calls as [[number]];
  const [[cuerpo]] = res.json.mock.calls as [
    [{ error: { code: string; message: string } }],
  ];
  return { status, error: cuerpo.error };
}

describe('HttpExceptionFilter — mensajes en español (RNF-01, T-071)', () => {
  beforeEach(() => {
    // El caso "error inesperado" registra el error real; no ensucia la salida.
    vi.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
  });

  describe('lo que ya venía en español pasa intacto', () => {
    it('DominioException conserva su code y su message', () => {
      const r = responder(
        new DominioException('X_INVALIDO', 'Esto es un mensaje propio.', HttpStatus.CONFLICT),
      );
      expect(r).toEqual({
        status: 409,
        error: { code: 'X_INVALIDO', message: 'Esto es un mensaje propio.' },
      });
    });

    it('los mensajes de validación propios de los DTO se unen con "; " sin cambios', () => {
      const r = responder(
        new BadRequestException(['El nombre es obligatorio.', 'La contraseña es obligatoria.']),
      );
      expect(r.status).toBe(400);
      expect(r.error).toEqual({
        code: 'VALIDACION',
        message: 'El nombre es obligatorio.; La contraseña es obligatoria.',
      });
    });

    it('un error que no es HttpException sigue siendo un 500 genérico en español', () => {
      const r = responder(new Error('boom interno'));
      expect(r).toEqual({
        status: 500,
        error: {
          code: 'ERROR_INTERNO',
          message: 'Ocurrió un error inesperado. Intenta de nuevo más tarde.',
        },
      });
    });
  });

  describe('mensajes de class-validator que no se pueden personalizar por decorador', () => {
    it('propiedad no permitida (forbidNonWhitelisted): "property foo should not exist"', () => {
      const r = responder(new BadRequestException(['property foo should not exist']));
      expect(r.error).toEqual({
        code: 'VALIDACION',
        message: 'La propiedad foo no está permitida.',
      });
    });

    it('se traduce solo el fragmento en inglés y se conservan los demás', () => {
      const r = responder(
        new BadRequestException(['El nombre es obligatorio.', 'property foo should not exist']),
      );
      expect(r.error.message).toBe(
        'El nombre es obligatorio.; La propiedad foo no está permitida.',
      );
    });

    it('lista anidada que no es objeto: "each value in nested property registros must be either object or array"', () => {
      const r = responder(
        new BadRequestException([
          'each value in nested property registros must be either object or array',
        ]),
      );
      expect(r.error.message).toBe('Cada elemento de registros debe ser un objeto.');
    });
  });

  describe('mensajes de Nest, multer y body-parser (mensaje suelto en inglés)', () => {
    it('un 413 suelto ("File too large", "request entity too large"...) cae al mensaje por estado (la subida de audio lo atiende ArchivoDemasiadoGrandeFilter)', () => {
      const r = responder(new PayloadTooLargeException('File too large'));
      expect(r).toEqual({
        status: 413,
        error: {
          code: 'CONTENIDO_DEMASIADO_GRANDE',
          message: 'El contenido enviado es demasiado grande.',
        },
      });
    });

    it('multer: campo de archivo con otro nombre ("Unexpected field - archivo")', () => {
      const r = responder(new BadRequestException('Unexpected field - archivo'));
      expect(r).toEqual({
        status: 400,
        error: {
          code: 'CAMPO_ARCHIVO_INESPERADO',
          message: 'Campo de archivo inesperado: archivo.',
        },
      });
    });

    it('ruta inexistente ("Cannot GET /x")', () => {
      const r = responder(new NotFoundException('Cannot GET /nada-por-aqui'));
      expect(r).toEqual({
        status: 404,
        error: { code: 'RUTA_NO_ENCONTRADA', message: 'La ruta solicitada no existe.' },
      });
    });

    it('cuerpo JSON malformado (mensaje de JSON.parse) → 400 genérico en español', () => {
      const r = responder(new BadRequestException('Unexpected end of JSON input'));
      expect(r).toEqual({
        status: 400,
        error: { code: 'PETICION_INVALIDA', message: 'La petición no es válida.' },
      });
    });

    it('excepciones nativas sin mensaje propio caen a un mensaje por estado', () => {
      expect(responder(new UnauthorizedException()).error).toEqual({
        code: 'SESION_REQUERIDA',
        message: 'Debes iniciar sesión para hacer esto.',
      });
      expect(responder(new ForbiddenException()).error).toEqual({
        code: 'PROHIBIDO',
        message: 'No tienes permiso para hacer esto.',
      });
      expect(responder(new NotFoundException()).error).toEqual({
        code: 'NO_ENCONTRADO',
        message: 'No se encontró lo que buscas.',
      });
    });

    it('un estado sin mensaje previsto cae al genérico en español, nunca al texto en inglés', () => {
      const r = responder(new HttpException('Something odd happened', 418));
      expect(r.status).toBe(418);
      expect(r.error).toEqual({
        code: 'ERROR',
        message: 'Ocurrió un error inesperado. Intenta de nuevo más tarde.',
      });
    });

    it('un HttpException con texto plano en inglés también se traduce', () => {
      const r = responder(new HttpException('Forbidden resource', 403));
      expect(r.error.message).toBe('No tienes permiso para hacer esto.');
    });
  });
});

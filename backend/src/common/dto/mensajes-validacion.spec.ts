// Los decoradores de class-transformer (@Type) necesitan el polyfill de
// Reflect: Nest lo carga al arrancar la app, una prueba unitaria no.
import 'reflect-metadata';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { getMetadataStorage } from 'class-validator';
import { describe, expect, it } from 'vitest';
import { FiltrosAlumnosDto } from '../../admin-alumnos/dto/filtros-alumnos.dto.js';
import { CambiarPasswordDto } from '../../auth/dto/cambiar-password.dto.js';
import { LoginDto } from '../../auth/dto/login.dto.js';
import { RecuperarPasswordDto } from '../../auth/dto/recuperar-password.dto.js';
import { RegistroAlumnoDto } from '../../auth/dto/registro-alumno.dto.js';
import { RestablecerPasswordDto } from '../../auth/dto/restablecer-password.dto.js';
import { CrearPalabraDto } from '../../palabras/dto/crear-palabra.dto.js';
import { EditarPalabraDto } from '../../palabras/dto/editar-palabra.dto.js';
import { OcultarPalabraDto } from '../../palabras/dto/ocultar-palabra.dto.js';
import { GuardarPracticaDto } from '../../practica/dto/guardar-practica.dto.js';
import { RegistroPracticaPendienteDto } from '../../practica/dto/registro-practica-pendiente.dto.js';
import { SincronizarPracticaDto } from '../../practica/dto/sincronizar-practica.dto.js';
import { RachaQueryDto } from '../../racha/dto/racha-query.dto.js';
import { PaginacionDto } from './paginacion.dto.js';

// T-071 (RNF-01). Los mensajes de validación llegan tal cual a la pantalla de
// la app Flutter (ApiException.message → SnackBar). class-validator los
// genera en INGLÉS ("nombre must be a string") cuando un decorador no trae
// `message`. Esta prueba obliga a que todo validador de todo DTO tenga uno
// propio, en español — para que agregar un DTO nuevo sin mensaje falle aquí y
// no en la pantalla de una persona.

const DTOS = {
  CambiarPasswordDto,
  CrearPalabraDto,
  EditarPalabraDto,
  FiltrosAlumnosDto,
  GuardarPracticaDto,
  LoginDto,
  OcultarPalabraDto,
  PaginacionDto,
  RachaQueryDto,
  RecuperarPasswordDto,
  RegistroAlumnoDto,
  RegistroPracticaPendienteDto,
  RestablecerPasswordDto,
  SincronizarPracticaDto,
};

function archivosDto(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const ruta = join(dir, e.name);
    if (e.isDirectory()) return e.name === 'generated' ? [] : archivosDto(ruta);
    return e.name.endsWith('.dto.ts') ? [ruta] : [];
  });
}

// Palabras inglesas que no existen en español (se evitan las que sí, como
// "error", "total" o "token").
const INGLES = new Set([
  'must', 'should', 'shall', 'be', 'is', 'are', 'not', 'the', 'an', 'of', 'to',
  'and', 'or', 'unexpected', 'too', 'large', 'invalid', 'string', 'number',
  'integer', 'array', 'empty', 'longer', 'shorter', 'characters', 'property',
  'exist', 'expected', 'field', 'file', 'value', 'valid', 'required', 'missing',
  'boolean', 'object', 'each', 'nested', 'either', 'greater', 'less', 'than',
]);
const palabrasEnIngles = (texto: string) =>
  (texto.toLowerCase().match(/[\p{L}]+/gu) ?? []).filter((p) => INGLES.has(p));

describe('mensajes de validación de los DTO (RNF-01, T-071)', () => {
  it('esta prueba cubre TODOS los DTO del código (si agregas uno, agrégalo aquí)', () => {
    const declarados = archivosDto(join(process.cwd(), 'src'))
      .flatMap((f) => [...readFileSync(f, 'utf8').matchAll(/export class (\w+)/g)])
      .map((m) => m[1])
      .sort();
    expect(declarados).toEqual(Object.keys(DTOS).sort());
  });

  it('todo validador de cada DTO trae un mensaje propio (si no, class-validator lo genera en inglés)', () => {
    const sinMensaje: string[] = [];
    for (const [nombre, Dto] of Object.entries(DTOS)) {
      const metadatos = getMetadataStorage().getTargetValidationMetadatas(
        Dto,
        '',
        false,
        false,
      );
      for (const meta of metadatos) {
        // @IsOptional()/@ValidateIf() no producen mensajes: solo deciden si se valida.
        if (meta.type === 'conditionalValidation') continue;
        if (meta.message === undefined) {
          sinMensaje.push(
            `${nombre}.${meta.propertyName} (${meta.name ?? meta.type})`,
          );
        }
      }
    }
    expect(sinMensaje).toEqual([]);
  });

  it('ningún mensaje propio de los DTO contiene palabras en inglés', () => {
    const ofensas: string[] = [];
    for (const [nombre, Dto] of Object.entries(DTOS)) {
      const metadatos = getMetadataStorage().getTargetValidationMetadatas(
        Dto,
        '',
        false,
        false,
      );
      for (const meta of metadatos) {
        if (typeof meta.message !== 'string') continue;
        const ingles = palabrasEnIngles(meta.message);
        if (ingles.length > 0) {
          ofensas.push(`${nombre}.${meta.propertyName}: «${meta.message}» [${ingles.join(', ')}]`);
        }
      }
    }
    expect(ofensas).toEqual([]);
  });

  it('el detector de inglés de esta prueba funciona (marca inglés y deja pasar español)', () => {
    expect(palabrasEnIngles('property foo should not exist')).not.toEqual([]);
    expect(palabrasEnIngles('each value in nested property x must be either object or array')).not.toEqual([]);
    expect(palabrasEnIngles('La contraseña debe tener al menos 8 caracteres.')).toEqual([]);
    expect(palabrasEnIngles('registros no puede ser un arreglo vacío.')).toEqual([]);
  });
});

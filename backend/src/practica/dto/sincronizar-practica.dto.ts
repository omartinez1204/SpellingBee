import { Type } from 'class-transformer';
import { ArrayNotEmpty, IsArray, ValidateNested } from 'class-validator';
import { RegistroPracticaPendienteDto } from './registro-practica-pendiente.dto.js';

// T-063 (RF-33): body de POST /practica/sync — el arreglo completo que la
// cola offline de Flutter (T-062, SincronizadorPractica) acumuló mientras
// no había conexión. El cliente real (SincronizadorPractica.
// intentarSincronizar()) NUNCA llama a este endpoint con la cola vacía —
// revisa explícitamente que haya algo pendiente antes de intentar — así que
// un arreglo vacío aquí solo puede venir de un cliente distinto o de un
// error; se rechaza con 400 en vez de aceptarlo como "nada que hacer", para
// que ese caso sea visible en vez de silencioso.
export class SincronizarPracticaDto {
  @IsArray({ message: 'registros debe ser un arreglo.' })
  @ArrayNotEmpty({ message: 'registros no puede ser un arreglo vacío.' })
  // T-071 (RNF-01): sin `message`, class-validator usa su texto en inglés
  // ("each value in nested property registros must be either object or array").
  @ValidateNested({
    each: true,
    message: 'Cada elemento de registros debe ser un objeto.',
  })
  @Type(() => RegistroPracticaPendienteDto)
  registros!: RegistroPracticaPendienteDto[];
}

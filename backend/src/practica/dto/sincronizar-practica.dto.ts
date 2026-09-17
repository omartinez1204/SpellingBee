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
  @ValidateNested({ each: true })
  @Type(() => RegistroPracticaPendienteDto)
  registros!: RegistroPracticaPendienteDto[];
}

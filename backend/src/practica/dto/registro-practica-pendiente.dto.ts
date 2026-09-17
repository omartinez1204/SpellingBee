import { IsNotEmpty, IsString } from 'class-validator';
import { GuardarPracticaDto } from './guardar-practica.dto.js';

// T-063 (RF-33). Mismos 5 campos que POST /practica (T-045, ver
// GuardarPracticaDto) más el `id` generado en el CLIENTE
// (app/lib/core/id_cliente.dart) — la llave de deduplicación que hace
// idempotente a POST /practica/sync (docs/diseno-tecnico.md §3.6). No se
// exige formato UUID estricto: lo único que el servidor necesita es una
// cadena no vacía que sirva como llave única, no atarse a un esquema de
// generación particular del cliente.
export class RegistroPracticaPendienteDto extends GuardarPracticaDto {
  @IsString({ message: 'id debe ser una cadena.' })
  @IsNotEmpty({ message: 'id es obligatorio.' })
  id!: string;
}

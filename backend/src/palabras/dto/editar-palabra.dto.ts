import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

// RF-09: cualquier profesor edita cualquier campo, de cualquier otro (no hay
// propiedad individual sobre las palabras). Todo opcional (PATCH parcial).
// Deliberadamente NO incluye:
//  - oculta: tiene su propio endpoint dedicado (PATCH .../ocultar, RF-10).
//  - completa: es un campo calculado por trigger (T-022), nunca a mano.
//  - nombre_archivo_audio: exclusivo de POST .../audio (RF-11, T-025).
//  - id_profesor_autor: es un dato histórico de quién la dio de alta, no
//    algo que una edición deba poder reasignar.
//
// significado_es/oracion_ejemplo aceptan null explícito para poder BORRAR
// un valor ya capturado (no solo agregarlo) — @IsOptional() de
// class-validator trata null igual que undefined (omite el resto de
// validadores de esa propiedad), así que un null explícito sí llega intacto
// al servicio en vez de ser rechazado por @IsString().
export class EditarPalabraDto {
  @IsOptional()
  @IsString({ message: 'El texto debe ser una cadena.' })
  texto?: string;

  @IsOptional()
  @IsInt({ message: 'El id de nivel debe ser un número entero.' })
  @Min(1, { message: 'El id de nivel debe ser un número entero positivo.' })
  @Max(Number.MAX_SAFE_INTEGER, { message: 'El id de nivel no es válido.' })
  id_nivel?: number;

  @IsOptional()
  @IsString({ message: 'El significado debe ser una cadena.' })
  significado_es?: string | null;

  @IsOptional()
  @IsString({ message: 'La oración de ejemplo debe ser una cadena.' })
  oracion_ejemplo?: string | null;
}

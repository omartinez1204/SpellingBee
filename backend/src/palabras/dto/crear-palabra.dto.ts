import { IsInt, IsNotEmpty, IsOptional, IsString, Max, Min } from 'class-validator';

// RF-08: texto + id_nivel obligatorios; significado_es/oracion_ejemplo
// opcionales (pueden completarse después — el propio catálogo del Anexo B
// llega así, sin esos 3 campos). nombre_archivo_audio NO se acepta aquí:
// eso es exclusivo de POST /admin/palabras/:id/audio (RF-11, T-025, todavía
// no implementado), porque ese nombre lo genera el backend a partir del id,
// nunca un texto libre que mande el cliente.
export class CrearPalabraDto {
  @IsString({ message: 'El texto debe ser una cadena.' })
  @IsNotEmpty({ message: 'El texto es obligatorio.' })
  texto!: string;

  @IsInt({ message: 'El id de nivel debe ser un número entero.' })
  @Min(1, { message: 'El id de nivel debe ser un número entero positivo.' })
  @Max(Number.MAX_SAFE_INTEGER, { message: 'El id de nivel no es válido.' })
  id_nivel!: number;

  @IsOptional()
  @IsString({ message: 'El significado debe ser una cadena.' })
  significado_es?: string;

  @IsOptional()
  @IsString({ message: 'La oración de ejemplo debe ser una cadena.' })
  oracion_ejemplo?: string;
}

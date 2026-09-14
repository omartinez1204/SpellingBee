import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';
import { CARRERAS } from '../../common/carreras.js';
import { PaginacionDto } from '../../common/dto/paginacion.dto.js';

// RF-30 (T-052): filtros opcionales y combinables sobre GET /admin/alumnos y
// GET /admin/alumnos/:id. Los 3 son independientes entre sí — el profesor
// puede mandar uno, varios o ninguno, y el resultado debe cumplir
// simultáneamente todos los que estén presentes (ver AdminAlumnosService).
export class FiltrosAlumnosDto extends PaginacionDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'nivel debe ser un número entero.' })
  @Min(1, { message: 'nivel debe ser un número entero positivo.' })
  nivel?: number;

  @IsOptional()
  @IsIn(CARRERAS, { message: `carrera debe ser una de: ${CARRERAS.join(', ')}.` })
  carrera?: (typeof CARRERAS)[number];

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'semestre debe ser un número entero.' })
  @Min(1, { message: 'semestre mínimo es 1.' })
  @Max(10, { message: 'semestre máximo es 10.' })
  semestre?: number;
}

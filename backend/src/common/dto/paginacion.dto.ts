import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';

const LIMITE_DEFECTO = 20;
// RNF-12: "sin traer todos los registros de la base de datos en una sola
// consulta" — el tope evita que el cliente pida de más aunque quisiera.
const LIMITE_MAXIMO = 50;

// Query params compartidos por cualquier listado paginado (RNF-12). Los
// valores llegan como texto en la query string; @Type(() => Number) los
// convierte antes de validarlos (el ValidationPipe global ya tiene
// transform: true).
export class PaginacionDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'pagina debe ser un número entero.' })
  @Min(1, { message: 'pagina debe ser al menos 1.' })
  pagina: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'limite debe ser un número entero.' })
  @Min(1, { message: 'limite debe ser al menos 1.' })
  @Max(LIMITE_MAXIMO, { message: `limite no puede exceder ${LIMITE_MAXIMO}.` })
  limite: number = LIMITE_DEFECTO;
}

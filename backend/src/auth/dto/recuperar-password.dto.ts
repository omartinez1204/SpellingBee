import { IsNotEmpty, IsString } from 'class-validator';

// RF-03. Mismo campo que login: sirve para matrícula (alumno) o username (profesor).
export class RecuperarPasswordDto {
  @IsString({ message: 'El nombre de usuario debe ser texto.' })
  @IsNotEmpty({ message: 'El nombre de usuario es obligatorio.' })
  nombre_usuario!: string;
}

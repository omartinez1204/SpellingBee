import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// RF-01 (alumno, con matrícula) / RF-02 (profesor, con username): mismo
// endpoint, mismo campo — nombreUsuario ya es la misma columna para ambos
// roles (ver Usuario.nombreUsuario en schema.prisma).
export class LoginDto {
  @IsString({ message: 'El nombre de usuario debe ser texto.' })
  @IsNotEmpty({ message: 'El nombre de usuario es obligatorio.' })
  nombre_usuario!: string;

  // bcrypt trunca en 72 bytes; sin tope, una cadena absurdamente larga igual
  // se "compararía" (siempre contra los primeros 72 bytes) gastando CPU de más.
  @IsString({ message: 'La contraseña debe ser texto.' })
  @IsNotEmpty({ message: 'La contraseña es obligatoria.' })
  @MaxLength(72, { message: 'La contraseña no puede exceder 72 caracteres.' })
  contrasena!: string;
}

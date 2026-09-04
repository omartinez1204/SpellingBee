import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

// RF-03. El token viene del enlace que envía /auth/recuperar-password.
export class RestablecerPasswordDto {
  @IsString({ message: 'El token debe ser texto.' })
  @IsNotEmpty({ message: 'El token es obligatorio.' })
  token!: string;

  // Mismas reglas que la contraseña de registro (T-010): 8-72 caracteres
  // (72 porque bcrypt trunca en silencio más allá de eso).
  @IsString({ message: 'La contraseña debe ser texto.' })
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres.' })
  @MaxLength(72, { message: 'La contraseña no puede exceder 72 caracteres.' })
  contrasena_nueva!: string;
}

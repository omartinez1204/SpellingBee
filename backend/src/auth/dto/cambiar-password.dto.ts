import { IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

// RF-35/RF-36. Requiere sesión (JwtAuthGuard) — el usuario a cambiar es el
// del token, nunca un id que venga en el body.
export class CambiarPasswordDto {
  @IsString({ message: 'La contraseña actual debe ser texto.' })
  @IsNotEmpty({ message: 'La contraseña actual es obligatoria.' })
  contrasena_actual!: string;

  // Mismas reglas que en registro (T-010) y restablecer (T-013).
  @IsString({ message: 'La contraseña nueva debe ser texto.' })
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres.' })
  @MaxLength(72, { message: 'La contraseña no puede exceder 72 caracteres.' })
  contrasena_nueva!: string;
}

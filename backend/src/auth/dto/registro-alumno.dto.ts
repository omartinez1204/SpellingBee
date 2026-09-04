import {
  Equals,
  IsEmail,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

// RF-01/RF-37. Carrera: texto literal del ERS (no la forma abreviada que trae
// diseno-tecnico.md §2, que transcribió mal estos 3 valores). Semestre: 1-10.
const CARRERAS = [
  'Ingeniería en Agroalimentos',
  'Ingeniería en Desarrollo de Software',
  'Licenciatura en MiPymes',
] as const;

export class RegistroAlumnoDto {
  @IsString({ message: 'La matrícula debe ser texto.' })
  @IsNotEmpty({ message: 'La matrícula es obligatoria.' })
  matricula!: string;

  @IsString({ message: 'El nombre debe ser texto.' })
  @IsNotEmpty({ message: 'El nombre es obligatorio.' })
  nombre!: string;

  @IsString({ message: 'El apellido paterno debe ser texto.' })
  @IsNotEmpty({ message: 'El apellido paterno es obligatorio.' })
  apellido_paterno!: string;

  @IsString({ message: 'El apellido materno debe ser texto.' })
  @IsNotEmpty({ message: 'El apellido materno es obligatorio.' })
  apellido_materno!: string;

  @IsIn(CARRERAS, {
    message: `La carrera debe ser una de: ${CARRERAS.join(', ')}.`,
  })
  carrera!: (typeof CARRERAS)[number];

  @IsInt({ message: 'El semestre debe ser un número entero.' })
  @Min(1, { message: 'El semestre mínimo es 1.' })
  @Max(10, { message: 'El semestre máximo es 10.' })
  semestre!: number;

  @IsEmail({}, { message: 'El correo no tiene un formato válido.' })
  correo!: string;

  // bcrypt trunca en 72 bytes; MaxLength evita que una contraseña más larga
  // se hashee "recortada" sin que la persona lo note.
  @IsString({ message: 'La contraseña debe ser texto.' })
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres.' })
  @MaxLength(72, { message: 'La contraseña no puede exceder 72 caracteres.' })
  contrasena!: string;

  @Equals(true, { message: 'Debes aceptar el aviso de privacidad.' })
  acepto_aviso_privacidad!: boolean;
}

import { IsBoolean, IsInt, IsString, Matches, Min } from 'class-validator';

// T-045 (RF-21, RF-25, RF-26, RF-27). Solo estos 5 campos: ValidationPipe
// corre con forbidNonWhitelisted:true (ver app.config.ts), así que cualquier
// campo fuera de esta lista — en particular audio del alumno, expresamente
// prohibido por RF-27/RF-40 — hace que la petición entera se rechace con 400
// antes de que este DTO o el servicio lleguen a existir en memoria.
//
// oracion_alumno NO usa @IsNotEmpty(): RF-26 dice "puede escribir y guardar
// una oración de al menos 1 carácter" para aclarar que no se exige una
// oración gramaticalmente completa, no para bloquear un campo vacío — nada
// en el ERS dice que el sistema deba rechazar una oración vacía, y la propia
// pantalla (T-044) nunca trata "vacía" como un estado de error. Si el
// negocio quiere exigir mínimo 1 carácter aquí, es un cambio a confirmar,
// no algo que este DTO deba asumir en silencio.
//
// deletreo_correcto llega ya calculado por el cliente (RF-25 se verifica
// ordenando fichas en la app, T-043) — este endpoint no vuelve a evaluar el
// deletreo, solo lo persiste tal como lo manda la app.
//
// fecha_local (T-046, RF-23): la fecha calendario LOCAL DEL DISPOSITIVO en
// el momento de este intento, "YYYY-MM-DD" sin hora ni offset — el
// servidor la usa para actualizar la racha de días consecutivos y NUNCA
// debe sustituirla por su propio reloj (ver common/fecha-local.util.ts).
// Que sea una fecha real (no "2026-02-30") lo valida el servicio.
export class GuardarPracticaDto {
  @IsInt({ message: 'El id de palabra debe ser un número entero.' })
  @Min(1, { message: 'El id de palabra debe ser un número entero positivo.' })
  id_palabra!: number;

  @IsInt({ message: 'El tiempo en segundos debe ser un número entero.' })
  @Min(0, { message: 'El tiempo en segundos no puede ser negativo.' })
  tiempo_segundos!: number;

  @IsString({ message: 'La oración debe ser texto.' })
  oracion_alumno!: string;

  @IsBoolean({ message: 'El resultado del deletreo debe ser verdadero o falso.' })
  deletreo_correcto!: boolean;

  @Matches(/^\d{4}-\d{2}-\d{2}$/, {
    message: 'fecha_local debe tener el formato YYYY-MM-DD.',
  })
  fecha_local!: string;
}

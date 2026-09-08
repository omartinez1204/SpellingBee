import { IsBoolean } from 'class-validator';

// RF-10. Body: { "oculta": true | false }. Reversible; no toca ningún otro campo.
export class OcultarPalabraDto {
  @IsBoolean({ message: 'oculta debe ser verdadero o falso.' })
  oculta!: boolean;
}

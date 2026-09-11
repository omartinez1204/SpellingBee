import { Matches } from 'class-validator';

// GET /racha?fecha_local=YYYY-MM-DD (RF-23). El formato exacto se valida
// aquí; que sea una fecha real (rechazar "2026-02-30") lo valida el
// servicio con parsearFechaLocal — mismo reparto de responsabilidades que
// parsearIdDeRuta en las rutas con :id.
export class RachaQueryDto {
  @Matches(/^\d{4}-\d{2}-\d{2}$/, {
    message: 'fecha_local debe tener el formato YYYY-MM-DD.',
  })
  fecha_local!: string;
}

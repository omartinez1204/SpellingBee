import { SetMetadata } from '@nestjs/common';

export const VALIDAR_PROPIO_ALUMNO_KEY = 'validarPropioAlumno';

// RNF-08. Marca una ruta para que RolesGuard exija que el id de alumno
// solicitado sea el del propio JWT — salvo que quien pregunta sea profesor,
// que puede consultar a cualquiera (no hay Grupo/Curso, diseno-tecnico.md §2).
//
// `campo` es el nombre del route param o query param que trae ese id
// (default "id", p.ej. GET /algo/:id). Ejemplo de uso futuro:
//   @Get(':id')
//   @ValidarPropioAlumno('id')
//   miEndpoint(@Param('id') id: string) { ... }
export const ValidarPropioAlumno = (campo = 'id') =>
  SetMetadata(VALIDAR_PROPIO_ALUMNO_KEY, campo);

import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { InsigniasModule } from '../insignias/insignias.module.js';
import { RachaModule } from '../racha/racha.module.js';
import { PracticaController } from './practica.controller.js';
import { PracticaService } from './practica.service.js';

// AuthModule: JwtAuthGuard (usado por PracticaController) necesita
// JwtService, exportado desde ahí — mismo motivo que roles-guard.e2e-spec.ts
// documenta para cualquier módulo nuevo que proteja sus propias rutas.
// RachaModule: guardar un intento de práctica actualiza la racha del
// alumno como efecto colateral (RF-23, T-046) — PracticaService necesita
// RachaService para eso.
// InsigniasModule: por el mismo motivo, guardar un intento puede completar
// el 100% de un nivel y otorgar su insignia (RF-24, T-047).
@Module({
  imports: [AuthModule, RachaModule, InsigniasModule],
  controllers: [PracticaController],
  providers: [PracticaService],
})
export class PracticaModule {}

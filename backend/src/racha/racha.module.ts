import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { RachaController } from './racha.controller.js';
import { RachaService } from './racha.service.js';

// AuthModule: JwtAuthGuard (RachaController) necesita JwtService — mismo
// motivo documentado en PracticaModule. RachaService se exporta porque
// PracticaModule lo importa para actualizar la racha como efecto de
// guardar un intento de práctica (T-045/T-046).
@Module({
  imports: [AuthModule],
  controllers: [RachaController],
  providers: [RachaService],
  exports: [RachaService],
})
export class RachaModule {}

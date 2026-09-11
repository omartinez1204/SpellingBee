import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { InsigniasController } from './insignias.controller.js';
import { InsigniasService } from './insignias.service.js';

@Module({
  imports: [AuthModule],
  controllers: [InsigniasController],
  providers: [InsigniasService],
  exports: [InsigniasService],
})
export class InsigniasModule {}

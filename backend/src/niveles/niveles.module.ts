import { Module } from '@nestjs/common';
import { NivelesController } from './niveles.controller.js';
import { NivelesService } from './niveles.service.js';

@Module({
  controllers: [NivelesController],
  providers: [NivelesService],
})
export class NivelesModule {}

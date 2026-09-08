import { Module } from '@nestjs/common';
import { PalabrasController } from './palabras.controller.js';
import { PalabrasService } from './palabras.service.js';

@Module({
  controllers: [PalabrasController],
  providers: [PalabrasService],
})
export class PalabrasModule {}

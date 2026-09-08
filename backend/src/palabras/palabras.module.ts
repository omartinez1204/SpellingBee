import { Module } from '@nestjs/common';
import { AdminPalabrasController } from './admin-palabras.controller.js';
import { AdminPalabrasService } from './admin-palabras.service.js';
import { PalabrasController } from './palabras.controller.js';
import { PalabrasService } from './palabras.service.js';

@Module({
  controllers: [PalabrasController, AdminPalabrasController],
  providers: [PalabrasService, AdminPalabrasService],
})
export class PalabrasModule {}

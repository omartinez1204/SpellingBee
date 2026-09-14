import { Module } from '@nestjs/common';
import { AdminAlumnosController } from './admin-alumnos.controller.js';
import { AdminAlumnosService } from './admin-alumnos.service.js';

@Module({
  controllers: [AdminAlumnosController],
  providers: [AdminAlumnosService],
})
export class AdminAlumnosModule {}

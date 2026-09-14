import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { AdminAlumnosModule } from './admin-alumnos/admin-alumnos.module.js';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { AuthModule } from './auth/auth.module.js';
import { RolesGuard } from './auth/guards/roles.guard.js';
import { InsigniasModule } from './insignias/insignias.module.js';
import { NivelesModule } from './niveles/niveles.module.js';
import { PalabrasModule } from './palabras/palabras.module.js';
import { PracticaModule } from './practica/practica.module.js';
import { PrismaModule } from './prisma/prisma.module.js';
import { RachaModule } from './racha/racha.module.js';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    NivelesModule,
    PalabrasModule,
    PracticaModule,
    RachaModule,
    InsigniasModule,
    AdminAlumnosModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    // Global (T-015): protege /admin/* y las rutas con @ValidarPropioAlumno
    // en toda la app, no solo donde alguien se acuerde de aplicarlo.
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
})
export class AppModule {}

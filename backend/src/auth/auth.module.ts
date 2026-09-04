import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { MailModule } from '../mail/mail.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { JwtAuthGuard } from './guards/jwt-auth.guard.js';

const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret) {
  // Sin fallback a propósito: un secreto "por default" horneado en el código
  // sería un JWT falsificable por cualquiera que lea el repo.
  throw new Error(
    'JWT_SECRET no está definido. Configúralo en .env (ver .env.example).',
  );
}

// Segundos, no "8h": el tipo de expiresIn para un string es un literal
// acotado (StringValue de la librería ms), que no puede venir de un
// process.env.string en tiempo de compilación. Un número es segundos, sin
// ambigüedad y sin pelear con ese tipo.
const JWT_EXPIRES_IN_SEGUNDOS =
  Number(process.env.JWT_EXPIRES_IN) || 8 * 60 * 60;

@Module({
  imports: [
    JwtModule.register({
      secret: jwtSecret,
      signOptions: { expiresIn: JWT_EXPIRES_IN_SEGUNDOS },
    }),
    MailModule,
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtAuthGuard],
  // Exportados para que otros módulos (T-015 y en adelante) puedan proteger
  // sus propias rutas con el mismo guard/configuración, sin duplicarlos.
  exports: [JwtModule, JwtAuthGuard],
})
export class AuthModule {}

import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import { LoginDto } from './dto/login.dto.js';
import { RecuperarPasswordDto } from './dto/recuperar-password.dto.js';
import { RegistroAlumnoDto } from './dto/registro-alumno.dto.js';
import { RestablecerPasswordDto } from './dto/restablecer-password.dto.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // POST /auth/registro (RF-01, RF-37)
  @Post('registro')
  registro(@Body() dto: RegistroAlumnoDto) {
    return this.authService.registrarAlumno(dto);
  }

  // POST /auth/login (RF-01 alumno / RF-02 profesor)
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  // POST /auth/logout (RF-04)
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  logout() {
    return this.authService.logout();
  }

  // POST /auth/recuperar-password (RF-03)
  @Post('recuperar-password')
  @HttpCode(HttpStatus.OK)
  recuperarPassword(@Body() dto: RecuperarPasswordDto) {
    return this.authService.recuperarPassword(dto);
  }

  // POST /auth/restablecer-password (RF-03)
  @Post('restablecer-password')
  @HttpCode(HttpStatus.OK)
  restablecerPassword(@Body() dto: RestablecerPasswordDto) {
    return this.authService.restablecerPassword(dto);
  }
}

import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import { LoginDto } from './dto/login.dto.js';
import { RegistroAlumnoDto } from './dto/registro-alumno.dto.js';

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
}

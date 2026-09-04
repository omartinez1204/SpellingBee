import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { AuthService } from './auth.service.js';
import { CurrentUser } from './decorators/current-user.decorator.js';
import { CambiarPasswordDto } from './dto/cambiar-password.dto.js';
import { LoginDto } from './dto/login.dto.js';
import { RecuperarPasswordDto } from './dto/recuperar-password.dto.js';
import { RegistroAlumnoDto } from './dto/registro-alumno.dto.js';
import { RestablecerPasswordDto } from './dto/restablecer-password.dto.js';
import { JwtAuthGuard, type JwtPayload } from './guards/jwt-auth.guard.js';

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

  // PATCH /auth/cambiar-password (RF-35, RF-36). Requiere sesión — el guard
  // de roles (T-015) es aparte; este solo exige un JWT válido, sin importar el rol.
  @Patch('cambiar-password')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  cambiarPassword(
    @CurrentUser() user: JwtPayload,
    @Body() dto: CambiarPasswordDto,
  ) {
    return this.authService.cambiarPassword(user.sub, dto);
  }
}

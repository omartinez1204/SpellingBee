import { createParamDecorator, type ExecutionContext } from '@nestjs/common';
import type {
  JwtPayload,
  RequestConUsuario,
} from '../guards/jwt-auth.guard.js';

// Solo tiene sentido en una ruta con @UseGuards(JwtAuthGuard) — ese guard es
// quien realmente pone request.user.
export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): JwtPayload => {
    const request = context.switchToHttp().getRequest<RequestConUsuario>();
    return request.user;
  },
);

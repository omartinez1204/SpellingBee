import { join } from 'node:path';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { HttpExceptionFilter } from './common/filters/http-exception.filter.js';

// Compartido entre main.ts y los tests e2e para que ambos arranquen la app
// con la misma configuración real (pipes/filtros/estáticos), no una versión
// reducida.
export function configureApp(app: INestApplication): void {
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());

  // RF-11/RF-12: los audios subidos por T-025 se sirven como estáticos bajo
  // /assets/audios/<archivo>, la misma ruta que ya construye urlAudio() en
  // palabras.service.ts. Público a propósito (igual que /palabras/:id): un
  // alumno necesita poder reproducirlos sin ser profesor. El cast es seguro
  // porque este proyecto siempre corre sobre el adaptador Express (no hay
  // adaptador Fastify configurado en ningún lado) — se evita cambiar la
  // firma pública de configureApp(), que ya usan main.ts y 7 archivos de test.
  (app as NestExpressApplication).useStaticAssets(
    join(process.cwd(), 'assets'),
    { prefix: '/assets' },
  );
}

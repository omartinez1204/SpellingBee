import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.config.js';

describe('NivelesController (e2e) - GET /niveles', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  // RF-05: "El sistema debe mostrar los tres niveles disponibles: Nivel 1
  // (Fácil), Nivel 2 (Intermedio) y Nivel 3 (Difícil)".
  it('regresa los 3 niveles del seed, en orden Fácil/Intermedio/Difícil', async () => {
    const respuesta = await request(app.getHttpServer())
      .get('/niveles')
      .expect(200);

    expect(respuesta.body).toHaveLength(3);
    expect(respuesta.body).toEqual([
      { id: expect.any(Number), nombre: 'Fácil', orden: 1 },
      { id: expect.any(Number), nombre: 'Intermedio', orden: 2 },
      { id: expect.any(Number), nombre: 'Difícil', orden: 3 },
    ]);
  });

  it('no requiere sesión iniciada', async () => {
    // Sin encabezado Authorization: diseno-tecnico.md §3.2 no marca esta
    // ruta como protegida, a diferencia de las de admin (§3.3/§3.5).
    await request(app.getHttpServer()).get('/niveles').expect(200);
  });
});

import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaBetterSqlite3 } from '@prisma/adapter-better-sqlite3';
import { PrismaClient } from '../generated/prisma/client.js';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor() {
    super({
      adapter: new PrismaBetterSqlite3({
        url: process.env.DATABASE_URL ?? 'file:./dev.db',
      }),
    });
  }

  async onModuleInit() {
    await this.$connect();
    // ERS §7 / docs/diseno-tecnico.md §1: SQLite en modo WAL.
    // journal_mode se persiste en el archivo, pero se reafirma en cada
    // arranque por si el servicio corre alguna vez contra un .db nuevo.
    await this.$executeRawUnsafe('PRAGMA journal_mode = WAL;');
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}

import { Module } from '@nestjs/common';
import { DevMailService } from './dev-mail.service.js';
import { MAIL_SERVICE } from './mail.service.interface.js';

@Module({
  // PRODUCCIÓN: cambiar useClass por la implementación real (ver dev-mail.service.ts).
  providers: [{ provide: MAIL_SERVICE, useClass: DevMailService }],
  exports: [MAIL_SERVICE],
})
export class MailModule {}

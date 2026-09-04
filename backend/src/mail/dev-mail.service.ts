import { appendFile } from 'node:fs/promises';
import { Injectable, Logger } from '@nestjs/common';
import type { MailService } from './mail.service.interface.js';

// Implementación de desarrollo: NovaUniversitas todavía no da credenciales
// SMTP (ver docs/backlog.md, "Bloqueadores"), así que en vez de conectarse a
// un proveedor real, esto solo deja constancia del envío en consola y en un
// archivo de log local (dev-emails.log, ignorado por git — nunca se commitea
// un token real).
//
// PRODUCCIÓN: cuando existan las credenciales, se agrega una clase nueva
// (p.ej. SmtpMailService) que implemente MailService usando nodemailer u otro
// proveedor (SES, SendGrid, etc.), y se cambia el `useClass` en mail.module.ts
// por esa clase — AuthService no cambia, porque solo conoce la interfaz.
const RUTA_LOG = 'dev-emails.log';
const BASE_ENLACE_RESTABLECER =
  process.env.APP_RESET_PASSWORD_URL_BASE ??
  'https://app-spelling-bee.ejemplo/restablecer-password';

@Injectable()
export class DevMailService implements MailService {
  private readonly logger = new Logger(DevMailService.name);

  async enviarCorreoRestablecimiento(
    destinatario: string,
    nombreUsuario: string,
    token: string,
  ): Promise<void> {
    const enlace = `${BASE_ENLACE_RESTABLECER}?token=${token}`;

    this.logger.warn(
      `[correo simulado] Restablecimiento para "${nombreUsuario}" <${destinatario}>: ${enlace}`,
    );

    const entrada = {
      timestamp: new Date().toISOString(),
      tipo: 'restablecimiento_contrasena',
      destinatario,
      nombreUsuario,
      token,
      enlace,
    };
    await appendFile(RUTA_LOG, JSON.stringify(entrada) + '\n', 'utf8');
  }
}

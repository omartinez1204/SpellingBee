// Interfaz del servicio de correo. RF-03 solo necesita este único método hoy;
// si más adelante se agregan otros correos transaccionales, se extiende aquí.
export interface MailService {
  enviarCorreoRestablecimiento(
    destinatario: string,
    nombreUsuario: string,
    token: string,
  ): Promise<void>;
}

// Token de inyección: AuthService depende de esta interfaz, no de una clase
// concreta, para poder cambiar la implementación (dev -> producción) sin
// tocar quien la usa.
export const MAIL_SERVICE = Symbol('MAIL_SERVICE');

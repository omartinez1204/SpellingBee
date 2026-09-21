// RNF-01 (T-071): la app Flutter muestra tal cual el `message` que devuelve
// el backend (ApiException.message → SnackBar/banner). Los mensajes propios
// (DominioException y los `message` de cada DTO) ya están en español; estos
// son los que generan en INGLÉS las librerías —Nest, class-validator, multer,
// body-parser— y que sin traducir llegarían a la pantalla de una persona.

export interface ErrorTraducido {
  code: string;
  message: string;
}

export const MENSAJE_ERROR_GENERICO =
  'Ocurrió un error inesperado. Intenta de nuevo más tarde.';

// Mensaje por estado HTTP para las excepciones nativas de Nest que traen su
// texto por defecto en inglés ("Unauthorized", "Forbidden resource"...).
const POR_ESTADO: Record<number, ErrorTraducido> = {
  400: { code: 'PETICION_INVALIDA', message: 'La petición no es válida.' },
  401: {
    code: 'SESION_REQUERIDA',
    message: 'Debes iniciar sesión para hacer esto.',
  },
  403: { code: 'PROHIBIDO', message: 'No tienes permiso para hacer esto.' },
  404: { code: 'NO_ENCONTRADO', message: 'No se encontró lo que buscas.' },
  405: {
    code: 'METODO_NO_PERMITIDO',
    message: 'Ese método no está permitido en esta ruta.',
  },
  409: {
    code: 'CONFLICTO',
    message: 'La operación choca con algo que ya existe.',
  },
  413: {
    code: 'CONTENIDO_DEMASIADO_GRANDE',
    message: 'El contenido enviado es demasiado grande.',
  },
  415: {
    code: 'FORMATO_NO_COMPATIBLE',
    message: 'El formato del contenido enviado no es compatible.',
  },
  429: {
    code: 'DEMASIADAS_PETICIONES',
    message: 'Hay demasiadas peticiones. Espera un momento e inténtalo de nuevo.',
  },
};

// Mensajes de class-validator que NO se pueden personalizar por decorador:
// los genera el propio ValidationPipe (forbidNonWhitelisted) o vienen de un
// decorador sin `message`. Se traducen por fragmento, uno a uno.
const REGLAS_DE_VALIDACION: Array<[RegExp, (m: RegExpMatchArray) => string]> = [
  [
    /^property (.+) should not exist$/,
    (m) => `La propiedad ${m[1]} no está permitida.`,
  ],
  [
    /^each value in nested property (.+) must be either object or array$/,
    (m) => `Cada elemento de ${m[1]} debe ser un objeto.`,
  ],
];

export function traducirMensajeDeValidacion(mensaje: string): string {
  for (const [patron, traducir] of REGLAS_DE_VALIDACION) {
    const coincidencia = mensaje.match(patron);
    if (coincidencia) return traducir(coincidencia);
  }
  return mensaje;
}

// Mensajes sueltos en inglés que producen multer, body-parser y el
// enrutador de Nest.
const REGLAS_INTERNAS: Array<{
  estado: number;
  patron: RegExp;
  traducir: (m: RegExpMatchArray) => ErrorTraducido;
}> = [
  {
    // multer: LIMIT_UNEXPECTED_FILE.
    estado: 400,
    patron: /^Unexpected field(?: - (.+))?$/i,
    traducir: (m) => ({
      code: 'CAMPO_ARCHIVO_INESPERADO',
      message: m[1]
        ? `Campo de archivo inesperado: ${m[1]}.`
        : 'Campo de archivo inesperado.',
    }),
  },
  {
    // El enrutador de Nest para una ruta o método que no existe.
    estado: 404,
    patron: /^Cannot [A-Z]+ \S+/,
    traducir: () => ({
      code: 'RUTA_NO_ENCONTRADA',
      message: 'La ruta solicitada no existe.',
    }),
  },
];

/**
 * Traduce una excepción HTTP que NO es de dominio y trae un mensaje suelto
 * (no los del ValidationPipe): por regla si se reconoce, y si no por estado —
 * nunca se deja pasar un texto que podría estar en inglés.
 */
export function traducirErrorInterno(
  estado: number,
  mensaje: string,
): ErrorTraducido {
  for (const regla of REGLAS_INTERNAS) {
    if (regla.estado !== estado) continue;
    const coincidencia = mensaje.match(regla.patron);
    if (coincidencia) return regla.traducir(coincidencia);
  }
  return POR_ESTADO[estado] ?? { code: 'ERROR', message: MENSAJE_ERROR_GENERICO };
}

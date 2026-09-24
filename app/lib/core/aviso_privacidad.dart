// T-074 (RF-37, RNF-11): texto PROVISIONAL del aviso de privacidad.
//
// Contenido legal entregado por el equipo de desarrollo e integrado TAL CUAL,
// sin editarlo: no lo reformules, corrijas ni traduzcas aquí. Es un borrador
// temporal (él mismo lo dice): el contenido definitivo lo redacta y valida el
// área jurídica de NovaUniversitas antes del lanzamiento a producción. Cuando
// llegue, se reemplaza SOLO esta constante y se quitan las marcas de borrador:
// [avisoPrivacidadEncabezado] (abajo) y el "(borrador)" del título de la
// tarjeta y de la casilla en screens/registro_screen.dart. La prueba de
// app/test/registro_screen_test.dart guarda una copia independiente del
// texto: hay que actualizarla a la vez.
//
// Se muestra ÍNTEGRO en la propia pantalla de registro (no detrás de un
// enlace), antes de la casilla de aceptación, con [avisoPrivacidadEncabezado]
// encima.
const avisoPrivacidadTexto =
    'La Universidad NovaUniversitas, es responsable del tratamiento de tus datos personales conforme a esta app. '
    'Los datos que recabamos en tu registro (nombre, matrícula, carrera, semestre y demás campos solicitados) se usan únicamente para identificarte, darte seguimiento a tu progreso de práctica de inglés dentro de esta plataforma, y para que tus profesores puedan revisar tu avance. '
    'No compartimos tus datos con terceros ajenos a NovaUniversitas. '
    'Puedes ejercer tus derechos de acceso, rectificación, cancelación u oposición (derechos ARCO) escribiendo a noreply@novauniversitas.edu.mx.\n\n'
    'Este texto es un borrador temporal de trabajo. '
    'El contenido definitivo será redactado y validado por el área jurídica de NovaUniversitas antes del lanzamiento a producción de la aplicación móvil.  '
    'Atentamente: Equipo de desarrollo de la universidad';

// Encabezado de advertencia del aviso (T-074, indicado en la revisión): va como
// primera línea de la tarjeta, ENCIMA del texto legal. NO forma parte del texto
// legal de arriba (que no se toca): es la marca de borrador, y se quita cuando
// llegue el aviso definitivo de jurídica, junto con el "(borrador)" del título
// de la tarjeta y de la casilla en screens/registro_screen.dart. La prueba de
// app/test/registro_screen_test.dart guarda una copia independiente.
const avisoPrivacidadEncabezado = 'BORRADOR — PENDIENTE DE VALIDACIÓN JURÍDICA';

# Spelling Bee — Backlog de desarrollo

Backlog derivado del ERS v1.14 y de `diseno-tecnico.md`. Pensado para que Claude Code implemente **una tarea a la vez**, en el orden listado (respeta dependencias: cada fase se apoya en la anterior). Cada tarea trae su criterio de aceptación tomado literalmente (o casi) del campo `criterio` del RF correspondiente en el ERS — eso es lo que Claude Code debe verificar (con una prueba automatizada cuando sea razonable) antes de marcarla como hecha.

Convención de checklist: `[ ]` pendiente, `[x]` hecho. Marcar la casilla es parte de la tarea, no un paso aparte.

## Fase 0 — Configuración del proyecto

- [x] **T-000** Inicializar monorepo con `/backend` (NestJS + TypeScript) y `/app` (Flutter). Configurar linter/formatter en ambos y un `README.md` raíz con cómo levantar cada uno.
- [x] **T-001** Backend: configurar Prisma (o el ORM elegido) apuntando a SQLite en modo WAL (ERS §7). Crear el esquema inicial con las 6 entidades de `diseno-tecnico.md` §2 (Usuario, PerfilAlumno, Nivel, Palabra, RegistroPractica, Racha) y su primera migración.
- [x] **T-002** Backend: seed script que inserte los 3 niveles (Fácil/Intermedio/Difícil, RF-05) y las 2 cuentas de profesor (`profesorIngles`, `profesorInglesb`) con contraseña temporal y `debe_cambiar_contraseña = true` (RF-02, RF-36). **No escribir las contraseñas reales en el repo** — usar variables de entorno o generarlas aleatoriamente en el seed y mostrarlas una sola vez en consola.
- [x] **T-003** Backend: cargar el catálogo de 45 palabras del Anexo B del ERS (texto + nivel) vía seed o migración de datos. Significado/oración/audio quedan pendientes (bloqueado — ver "Bloqueadores" al final).

## Fase 1 — Autenticación (RF-01 a RF-04, RF-35 a RF-37)

- [x] **T-010** `POST /auth/registro` (RF-01, RF-37): valida los 8 campos obligatorios, unicidad de matrícula, y que `acepto_aviso_privacidad = true`. Hashea la contraseña (bcrypt). *Criterio:* un alumno nuevo solo puede crear cuenta llenando los 8 campos y aceptando el aviso; no puede registrarse dos veces con la misma matrícula.
- [x] **T-011** `POST /auth/login` (RF-01, RF-02): valida credenciales para alumno (matrícula) y profesor (username), emite JWT con `rol` y `debe_cambiar_contraseña`.
- [x] **T-012** `POST /auth/logout` (RF-04): endpoint stateless; documentar en el cliente que basta descartar el JWT localmente.
- [x] **T-013** `POST /auth/recuperar-password` + `POST /auth/restablecer-password` (RF-03): flujo de correo de restablecimiento, aplica a alumno y a las 2 cuentas de profesor.
- [x] **T-014** `PATCH /auth/cambiar-password` (RF-35, RF-36): valida contraseña actual; si la cuenta tenía `debe_cambiar_contraseña = true`, lo pone en `false` tras el cambio exitoso.
- [x] **T-015** Guard de NestJS por rol (`RolesGuard`) reutilizable para RNF-07 (bloquear `alumno` de rutas `/admin/*`) y RNF-08 (un alumno solo accede a sus propios registros).
- [x] **T-016** Flutter: pantallas de registro (con aviso de privacidad, RF-37), login, "olvidé mi contraseña", cambio de contraseña, y forzar la pantalla de cambio de contraseña en el primer login si `debe_cambiar_contraseña = true` (RF-36) sin poder omitirla.

## Fase 2 — Catálogo (RF-05 a RF-11, RF-39)

- [x] **T-020** `GET /niveles` (RF-05).
- [x] **T-021** `GET /niveles/:id/palabras` (RF-06): filtra `completa=true AND oculta=false`. *Criterio:* una palabra incompleta o oculta nunca aparece aquí.
- [x] **T-022** Lógica de `Palabra.completa` como campo calculado (recalcular en cada create/update, ver `diseno-tecnico.md` §2).
- [x] **T-023** `GET /palabras/:id` (RF-07): regresa los 4 campos siempre; la app decide qué ocultar tras pistas.
- [x] **T-024** `GET/POST/PATCH /admin/palabras*` y `PATCH /admin/palabras/:id/ocultar` (RF-08, RF-09, RF-10, RF-39), protegidos por rol profesor. *Criterio de RF-10:* ocultar/desocultar es inmediato y reversible, no borra nada ni afecta registros de práctica ya generados.
- [x] **T-025** `POST /admin/palabras/:id/audio` (RF-11): valida formato (mp3/aac/m4a) y tamaño (≤1 MB), guarda como `<id>.<ext>` en `assets/audios/`. *Criterio:* un archivo inválido se rechaza con mensaje claro; editar el texto de la palabra nunca desvincula su audio.
- [x] **T-026** Flutter: pantalla de práctica del alumno mostrando solo palabra + ícono de audio, con botones "Ver significado" / "Ver ejemplo" (RF-07 — diseño marcado como propuesta del equipo en el ERS, revisar con el cliente si el copy/UX definitivo cambia).
- [x] **T-027** Flutter: panel de administración del catálogo para profesores (RF-39) — lista completa con estado (completa/incompleta, oculta/visible) y acciones de agregar, editar, subir audio, ocultar/mostrar sin salir de la pantalla.

## Fase 3 — Reproductor de audio (RF-12 a RF-18)

- [x] **T-030** Reproducción básica (RF-12), pausa/reanuda (RF-13), detener (RF-16), reproducciones ilimitadas (RF-17).
- [x] **T-031** Retroceder/adelantar exactamente 5 segundos (RF-14, RF-15), sin pasar de 0 ni de la duración total.
- [x] **T-032** Barra de progreso + texto `mm:ss / mm:ss` actualizado al menos 1 vez por segundo (RF-18).
- [x] **T-033** Caché local del audio descargado para cumplir RNF-03 (reproducción en <2s si ya está disponible localmente).

## Fase 4 — Cronómetro, deletreo y oración (RF-19 a RF-27, RF-40)

- [x] **T-040** Botón de inicio + cronómetro único combinado en 00:00 hasta que el alumno lo activa (RF-19), actualizado en tiempo real (RF-20).
- [x] **T-041** Botón "Terminé" que detiene el cronómetro y fija el tiempo final (RF-21).
- [x] **T-042** `GET /practica/mejor-tiempo/:id_palabra` + UI de mensaje motivacional (mejora/empate/no-mejora) o mensaje de bienvenida en el primer intento (RF-22).
- [x] **T-043** Mecánica de bloques de letras para ordenar (estilo Duolingo), sin distractores, verificación solo por orden de fichas (RF-25).
- [x] **T-044** Campo de texto para la oración + validación de que la palabra practicada aparece como subcadena literal, sin distinguir mayúsculas/minúsculas (RF-26). No bloquea el guardado si falla.
- [x] **T-045** `POST /practica` (RF-21, RF-27): guarda tiempo, resultado de deletreo y oración; **nunca** acepta ni persiste audio del alumno.
- [x] **T-046** Racha de días consecutivos por fecha calendario **local del dispositivo** (RF-23) y `GET /racha`.
- [x] **T-047** Insignia + mensaje de felicitación al completar el 100% de un nivel (RF-24) y `GET /progreso/insignias`.
- [x] **T-048** Flutter: botón "Escúchate" (RF-40) — graba con el micrófono, reproduce una vez, borra el archivo del dispositivo de inmediato. 100% local, sin llamadas a la API. Opcional: el alumno puede terminar sin usarlo.

## Fase 5 — Seguimiento docente (RF-28 a RF-30)

- [x] **T-050** `GET /admin/alumnos` (RF-28) con avance general por alumno, paginado (RNF-12).
- [x] **T-051** `GET /admin/alumnos/:id` (RF-29): detalle palabra/tiempo/oración por intento, paginado.
- [x] **T-052** Filtros combinables `nivel`, `carrera`, `semestre` (RF-30) sobre ambos endpoints anteriores.
- [x] **T-053** Flutter: panel docente con tabla de alumnos, detalle y filtros.

## Fase 6 — Modo offline (RF-31 a RF-34, RF-38)

- [x] **T-060** `GET /niveles/:id/descarga` (RF-31): paquete de palabras + audios de un nivel.
- [x] **T-061** Flutter: descarga y almacenamiento local del paquete de nivel; práctica 100% funcional sin conexión usando ese contenido (RF-32).
- [x] **T-062** Flutter: cola local de registros de práctica generados offline; sincronización automática al detectar conectividad, con reintento cada 5 minutos hasta lograrlo, sin perder registros (RF-33).
- [x] **T-063** `POST /practica/sync` (RF-33): recepción en lote, idempotente por id generado en cliente.
- [x] **T-064** Flutter: indicador visual en línea/sin conexión y de registros pendientes, con confirmación transitoria al sincronizar con éxito (RF-34).
- [x] **T-065** Manejo uniforme de "backend no disponible" en el cliente: mensaje de error + reintentar, sin perder lo ya capturado en el formulario (RF-38).

## Fase 7 — No funcionales transversales

- [x] **T-070** Paginación en todos los listados que puedan superar 50 elementos (RNF-12).
- [x] **T-071** Revisión de que el 100% de los textos de interfaz están en español (RNF-01) — solo la palabra/oración léxica va en inglés.
- [ ] **T-072** Prueba de usabilidad guiada: un alumno completa su primera práctica sin ayuda externa (RNF-02).
- [ ] **T-073** Documentar con TI de NovaUniversitas la política de respaldo del archivo SQLite (RNF-13) — tarea operativa, no de código.
- [ ] **T-074** Aviso de privacidad: mostrar el texto en el registro (RF-37) — el contenido definitivo lo redacta el área jurídica de NovaUniversitas (RNF-11); mientras tanto usar un texto provisional claramente marcado como borrador.

## Bloqueadores heredados del ERS (no resolverlos por cuenta propia — preguntar)

Estos puntos, ya señalados en el ERS §8.2, detienen o limitan ciertas tareas de este backlog. Si Claude Code llega a una de ellas, debe señalarlo en vez de asumir una respuesta, siguiendo la instrucción permanente del cliente ("no asumas nada, pregúntame"):

- **T-003 / contenido del catálogo**: faltan significado, oración y audio de las 45 palabras — sin esto, ninguna palabra puede llegar a `completa=true` y por tanto ninguna es visible para un alumno real (RF-06, RF-08).
- **Servidor, dominio y política de respaldo (T-073)**: dependen de TI de NovaUniversitas.
- **Fecha límite del proyecto**: no definida en el ERS.
- **Texto legal del aviso de privacidad (T-074)**: pendiente de validación jurídica.
- **RF-07 (diseño de pistas "Ver significado"/"Ver ejemplo")**: es una propuesta del equipo de desarrollo, no una instrucción literal del cliente — confirmar antes de darla por definitiva si el cliente la revisa.
- **Palabra duplicada "requirement"** en el Anexo B (aparece dos veces en Difícil): no bloquea el desarrollo (cada fila es un registro independiente con su propio id y audio), pero es un asunto de calidad de contenido a resolver por los profesores.

# Spelling Bee — guía para Claude Code

App móvil Flutter de NovaUniversitas para que sus estudiantes de inglés practiquen pronunciación, deletreo (spelling) y construcción de oraciones con vocabulario organizado en 3 niveles de dificultad. Backend propio (no BaaS) en Node.js + NestJS, base de datos SQLite.

## Documentos fuente (en este orden de autoridad)

1. `Spelling_Bee_ERS_v1.14.docx` — Especificación de Requisitos de Software (ERS/SRS) formal, IEEE 830 / ISO-IEC-IEEE 29148. **Es la fuente de verdad del "qué".** Todo requisito tiene un id (RF-xx / RNF-xx), una prioridad, un criterio de aceptación verificable y su origen (qué dijo el cliente vs. qué propuso el equipo). Documento vivo: si cambia, cambia de versión, nunca se sobreescribe una versión anterior.
2. `docs/diseno-tecnico.md` — traduce el ERS al "cómo": modelo de datos, contrato de API, decisiones de arquitectura. Marca con **[decisión de equipo]** lo que no viene del cliente.
3. `docs/backlog.md` — el "qué hacer ahora": tareas atómicas, en orden de dependencia, cada una con su criterio de aceptación. **Trabaja de aquí, tarea por tarea.**

## Cómo trabajar en este repo

- Toma la siguiente tarea `[ ]` sin marcar de `docs/backlog.md`, en orden (respeta las fases — no implementes Fase 3 antes que Fase 1 salvo que la tarea lo permita explícitamente).
- Antes de darla por hecha: verifica su criterio de aceptación (idealmente con una prueba automatizada). Si el criterio es ambiguo o no se puede verificar tal cual está escrito, dilo — no lo relajes en silencio.
- Marca la casilla (`[x]`) en el mismo cambio que implementa la tarea.
- No implementes requisitos que no estén en el ERS ni en el backlog "porque tendría sentido" — si algo parece faltar, agrégalo primero como punto a confirmar (igual que el ERS documenta sus propios supuestos en la sección 8.2), no lo construyas por iniciativa propia.
- Si una tarea depende de un bloqueador listado al final de `docs/backlog.md` (contenido del catálogo, servidor/TI, aviso legal, etc.), no lo resuelvas con un valor inventado — usa un placeholder claramente marcado como temporal, o pausa esa tarea y pasa a la siguiente independiente.

## Reglas de negocio que no deben romperse

Estas son las más fáciles de violar por accidente al programar; están aquí porque cada una tiene una razón de negocio explícita en el ERS, no son arbitrarias:

- **Nunca se sube ni se guarda en el backend/base de datos audio grabado por un alumno** (ni el de deletreo ni el de su oración, RF-27, RF-40). La grabación de "Escúchate" es 100% local, de un solo uso, y se borra del dispositivo inmediatamente después de reproducirse. Si una tarea implica tocar algo de audio del alumno y termina llamando a la API, algo está mal.
- **"Ocultar" una palabra no es borrarla** (RF-10). Es un booleano reversible (`oculta`); el registro y su historial de práctica se conservan íntegros.
- **El archivo de audio de una palabra se nombra por su `id` interno, nunca por su texto** (RF-11) — así, corregir la ortografía de una palabra (RF-09) nunca desvincula su audio.
- **Un cambio de nivel de una palabra (RF-09) no reescribe el historial**: `RegistroPractica.id_nivel_en_practica` es un snapshot fijado al momento de practicar, y ninguna insignia o racha ya obtenida se revoca retroactivamente.
- **La racha (RF-23) se calcula con la fecha calendario local del dispositivo del alumno**, no la del servidor.
- **La verificación de deletreo (RF-25) es por orden de fichas/bloques de letras**, no por comparación de texto libre — no hay reglas de mayúsculas ni espacios que aplicar ahí (esas sí aplican a la oración, RF-26, que se compara como subcadena sin distinguir mayúsculas).
- **Toda la interfaz va en español** (RNF-01); solo la palabra en inglés y su oración de ejemplo van en inglés.
- **Rutas `/admin/*` (catálogo y seguimiento docente) son exclusivas del rol `profesor`** (RNF-07); un alumno nunca debe poder leer registros de otro alumno (RNF-08).
- **Un profesor con contraseña asignada manualmente debe cambiarla en su primer login**, sin poder omitir ese paso (RF-36). Nunca escribas contraseñas reales de las 2 cuentas de profesor en el código, en commits ni en este repo.

## Convenciones técnicas

Ver `docs/diseno-tecnico.md` para el detalle completo (entidades, endpoints). Resumen:

- Backend: NestJS + Prisma + SQLite (WAL). API REST bajo `/api/v1`, JSON, errores con forma `{ "error": { "code", "message" } }`.
- Auth: JWT con `rol` en el payload; contraseñas con bcrypt.
- Frontend: Flutter, mínimo Android 8.0 / API 26 (RNF-06).
- Listas que puedan superar 50 elementos van paginadas (RNF-12): alumnos y registros de práctica en el panel docente.

## Comandos

_(Pendiente de completar en cuanto exista el scaffolding real de `/backend` y `/app` — Fase 0 del backlog, tarea T-000. Actualiza esta sección con los comandos reales de test/build/lint apenas se definan, para que las siguientes sesiones de Claude Code no tengan que redescubrirlos.)_

- Backend test: `TBD`
- Backend build: `TBD`
- App Flutter run: `TBD`
- App Flutter test: `TBD`

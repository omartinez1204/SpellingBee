# Spelling Bee — Diseño técnico

Basado en el ERS v1.14 (`Spelling_Bee_ERS_v1.14.docx`). Este documento traduce los requisitos funcionales (RF) y no funcionales (RNF) del ERS a decisiones de arquitectura, modelo de datos y contrato de API, para que el desarrollo (con Claude Code) tenga una referencia técnica concreta sin tener que reinterpretar el ERS en cada tarea.

Convención: cada decisión de este documento cita el RF/RNF del que se deriva. Cuando una decisión es puramente técnica (no está en el ERS porque el cliente delegó el "cómo" al equipo de desarrollo), se marca como **[decisión de equipo]** — son libres de ajustarse durante el desarrollo sin volver a validar con el cliente, a diferencia de lo que el ERS marca como "a confirmar con el cliente" en su sección 8.2.

## 1. Arquitectura general

```
┌─────────────────┐        HTTPS / REST + JSON        ┌──────────────────────┐
│   App Flutter    │ ─────────────────────────────────▶│   Backend NestJS      │
│  (Android, RNF-06)│◀─────────────────────────────────│  (Node.js)            │
└─────────────────┘                                     │  ┌─────────────────┐ │
        │                                                │  │ SQLite (WAL)    │ │
        │ almacenamiento local                           │  │ RNF-13: respaldo│ │
        │ (cola offline RF-33, catálogo                  │  └─────────────────┘ │
        │  descargado RF-31, audio efímero RF-40)         │  assets/audios/*.mp3  │
        └────────────────────────────────────────────────└──────────────────────┘
```

- **Frontend**: Flutter, un solo código para Android (RNF-06: Android 8.0 / API 26+). No se contempla iOS en el ERS.
- **Backend**: Node.js + NestJS, API REST en JSON, alojado en el servidor de NovaUniversitas (pendiente de TI, ver ERS 8.2).
- **Base de datos**: SQLite en modo WAL, un solo archivo (ver ERS sección 7 y RNF-13 sobre respaldo).
- **Audio**: archivos estáticos servidos por el propio backend (`assets/audios/<id>.<ext>`), nunca en BLOB dentro de SQLite (RF-11).
- **[decisión de equipo] ORM**: Prisma, por su soporte directo de SQLite, migraciones versionadas en el repo y tipado compartido con NestJS. Alternativa aceptable: TypeORM; ajustar aquí si el equipo prefiere otra.
- **[decisión de equipo] Autenticación**: JWT firmado por el backend, emitido en login, enviado como `Authorization: Bearer <token>`. El payload incluye `sub` (id de usuario) y `rol` (alumno/profesor), usado para RNF-07 (restringir catálogo-admin y seguimiento a rol profesor) y RNF-08 (un alumno no puede ver registros de otro). No se define refresh token en esta primera versión: sesión expira y el usuario vuelve a iniciar sesión (simple, acorde al tamaño del proyecto).
- **[decisión de equipo] Hash de contraseña**: bcrypt (costo 10+), nunca texto plano, acorde a la entidad Usuario del ERS ("contraseña (hash, nunca en texto plano)").

## 2. Modelo de datos

Basado literalmente en el ERS §3.4. Tipos SQLite entre paréntesis.

```mermaid
erDiagram
    USUARIO ||--o| PERFIL_ALUMNO : "1:1 (solo alumnos)"
    USUARIO ||--o{ REGISTRO_PRACTICA : genera
    USUARIO ||--o| RACHA : tiene
    NIVEL ||--o{ PALABRA : agrupa
    PALABRA ||--o{ REGISTRO_PRACTICA : "se practica en"

    USUARIO {
        int id PK
        string nombre_usuario "matrícula (alumno) o username (profesor)"
        string contraseña_hash
        string rol "alumno | profesor"
        string correo_electronico
        bool debe_cambiar_contraseña "RF-36"
        string correo_recuperacion "solo profesor, RF-02/RF-03"
        datetime fecha_registro
    }
    PERFIL_ALUMNO {
        int id_usuario PK_FK
        string nombre
        string apellido_paterno
        string apellido_materno
        string carrera "enum: Ingeniería en Agroalimentos | Ingeniería en Desarrollo de Software | Licenciatura en MiPymes"
        int semestre "1-10"
    }
    NIVEL {
        int id PK
        string nombre "Fácil | Intermedio | Difícil"
        int orden
    }
    PALABRA {
        int id PK
        string texto
        int id_nivel FK
        string significado_es "nullable"
        string oracion_ejemplo "nullable"
        string nombre_archivo_audio "nullable, <id>.<ext>, RF-11"
        bool completa "calculado: 3 campos de contenido llenos"
        bool oculta "RF-10, default false"
        datetime fecha_alta
        int id_profesor_autor FK
    }
    REGISTRO_PRACTICA {
        int id PK
        int id_alumno FK
        int id_palabra FK
        int id_nivel_en_practica "snapshot, RF-09"
        int tiempo_segundos
        string oracion_alumno
        bool deletreo_correcto
        datetime fecha_hora
        bool sincronizado "RF-33"
    }
    RACHA {
        int id_alumno PK_FK
        int dias_consecutivos
        date ultima_fecha_practica "fecha calendario LOCAL del alumno, RF-23"
    }
```

Notas de implementación derivadas del ERS:

- `Palabra.completa` es un campo **calculado**, no capturado directamente: `completa = significado_es != null AND oracion_ejemplo != null AND nombre_archivo_audio != null` (RF-08). Recomendación: recalcularlo en cada `UPDATE` de Palabra (trigger SQLite o lógica en el servicio NestJS), no dejarlo desincronizable a mano.
- `Palabra.nombre_archivo_audio` se genera a partir del **id interno**, nunca del texto (RF-11) — así, editar el texto de una palabra (RF-09) nunca rompe la asociación con su audio.
- `RegistroPractica.id_nivel_en_practica` se copia del nivel de la palabra **al momento de guardar el registro**, no se recalcula después — esto es lo que hace que un cambio de nivel posterior (RF-09) no altere el historial ni revoque insignias/rachas ya obtenidas.
- No existe entidad Grupo/Curso (confirmado con el cliente, ERS §3.4): todo profesor ve a todos los alumnos por igual.
- Los audios del alumno (autopráctica, RF-40) **nunca** llegan a esta base de datos ni al backend; viven y mueren en el dispositivo. No hay tabla ni campo para ellos — omitirlos del modelo es intencional, no un olvido.

## 3. Contrato de API (REST, JSON)

Prefijo sugerido: `/api/v1`. Formato de error uniforme para todos los endpoints (soporta RF-38 en el cliente):

```json
{ "error": { "code": "AUDIO_FORMATO_INVALIDO", "message": "El archivo debe ser MP3, AAC o M4A." } }
```

### 3.1 Autenticación (RF-01 a RF-04, RF-35 a RF-37)

| Método y ruta | RF | Descripción |
|---|---|---|
| `POST /auth/registro` | RF-01, RF-37 | Alta de alumno. Body: matrícula, nombre, apellido_paterno, apellido_materno, carrera, semestre, correo, contraseña, `acepto_aviso_privacidad: true` (obligatorio). Rechaza matrícula duplicada. |
| `POST /auth/login` | RF-01, RF-02 | Body: `nombre_usuario`, `contraseña`. Responde JWT + rol + `debe_cambiar_contraseña`. |
| `POST /auth/logout` | RF-04 | Invalida el token del lado cliente (stateless; el cliente simplemente descarta el JWT). |
| `POST /auth/recuperar-password` | RF-03 | Body: `nombre_usuario`. Envía correo de restablecimiento al correo registrado (alumno o profesor). |
| `POST /auth/restablecer-password` | RF-03 | Body: token del correo + nueva contraseña. |
| `PATCH /auth/cambiar-password` | RF-35, RF-36 | Requiere sesión. Body: contraseña_actual, contraseña_nueva. Si la cuenta tenía `debe_cambiar_contraseña = true`, este endpoint lo pone en `false`. |
| `GET /auth/perfil` | — | Devuelve el usuario en sesión (para que el cliente sepa el rol y si debe forzar el cambio de contraseña, RF-36). |

### 3.2 Catálogo — vista alumno (RF-05, RF-06, RF-07)

| Método y ruta | RF | Descripción |
|---|---|---|
| `GET /niveles` | RF-05 | Lista los 3 niveles. |
| `GET /niveles/:id/palabras` | RF-06 | Solo palabras `completa=true AND oculta=false` de ese nivel. |
| `GET /palabras/:id` | RF-07 | Detalle completo (palabra, significado, oración, url de audio). **El ocultamiento de significado/oración tras las pistas es responsabilidad del cliente Flutter**, no del backend: el backend siempre regresa los 4 campos; la UI decide qué mostrar de entrada y qué revelar con los botones "Ver significado"/"Ver ejemplo". |

### 3.3 Catálogo — administración docente (RF-08 a RF-11, RF-39)

Todas requieren rol `profesor` (RNF-07).

| Método y ruta | RF | Descripción |
|---|---|---|
| `GET /admin/palabras` | RF-39 | Lista TODAS las palabras (completas/incompletas, ocultas/visibles) con sus 4 campos de contenido + estado. Paginado (RNF-12). |
| `POST /admin/palabras` | RF-08 | Body mínimo: `texto`, `id_nivel`. `significado_es`, `oracion_ejemplo` opcionales al crear. |
| `PATCH /admin/palabras/:id` | RF-09 | Edita cualquier campo, de cualquier profesor (catálogo compartido). |
| `PATCH /admin/palabras/:id/ocultar` | RF-10 | Body: `{ "oculta": true \| false }`. Reversible, no borra nada. |
| `POST /admin/palabras/:id/audio` | RF-11 | Multipart. Valida formato (mp3/aac/m4a) y tamaño (≤1 MB). Guarda como `<id>.<ext>` en `assets/audios/`. |

### 3.4 Práctica y deletreo (RF-19 a RF-27, RF-40)

| Método y ruta | RF | Descripción |
|---|---|---|
| `GET /practica/mejor-tiempo/:id_palabra` | RF-22 | Mejor tiempo previo del alumno en sesión para esa palabra, o `null` si es su primer intento. |
| `POST /practica` | RF-21, RF-25, RF-26, RF-27 | Body: `id_palabra`, `tiempo_segundos`, `oracion_alumno`, `deletreo_correcto` (calculado en el cliente al ordenar las fichas, RF-25, y reenviado; el backend puede además re-validar la oración con RF-26 antes de guardar). Actualiza Racha (RF-23) y evalúa insignia de nivel (RF-24) como efecto del guardado. |
| `GET /racha` | RF-23 | Racha actual del alumno en sesión. |
| `GET /progreso/insignias` | RF-24 | Insignias de nivel obtenidas por el alumno en sesión. |

RF-40 (grabarse y escucharse) **no tiene endpoint**: es 100% local en Flutter (grabar con el micrófono, reproducir una vez, borrar el archivo del dispositivo). Ningún dato de esa función sale del teléfono.

### 3.5 Seguimiento docente (RF-28 a RF-30)

Todas requieren rol `profesor`.

| Método y ruta | RF | Descripción |
|---|---|---|
| `GET /admin/alumnos` | RF-28, RF-30 | Lista alumnos + avance general. Query params opcionales y combinables: `nivel`, `carrera`, `semestre`. Paginado (RNF-12). |
| `GET /admin/alumnos/:id` | RF-29 | Detalle: palabra, tiempo, oración por cada intento del alumno. Paginado (RNF-12). |

### 3.6 Modo offline (RF-31 a RF-34, RF-38)

| Método y ruta | RF | Descripción |
|---|---|---|
| `GET /niveles/:id/descarga` | RF-31 | Paquete completo del nivel: todas las palabras completas y no ocultas + URLs de audio, pensado para que el cliente descargue también los binarios de audio y los cachee localmente. |
| `POST /practica/sync` | RF-33 | Body: arreglo de registros de práctica generados offline (mismo shape que `POST /practica`, en lote). Debe ser idempotente (un registro reenviado por reintento no debe duplicarse — usar un id generado en el cliente, ej. UUID, como llave de deduplicación). |

El manejo de "backend no disponible" (RF-38) es responsabilidad del cliente Flutter: reintentar la llamada y no perder el formulario capturado; no requiere un endpoint especial.

## 4. No funcionales relevantes al diseño

- **RNF-03** (audio < 2s si ya está descargado/cacheado): el cliente Flutter debe cachear el audio descargado (RF-31) en almacenamiento local, no volver a pedirlo a cada reproducción.
- **RNF-07 / RNF-08** (seguridad): todo endpoint bajo `/admin/*` valida rol `profesor` vía guard de NestJS; todo endpoint que devuelve datos de un alumno específico valida que el `id_alumno` solicitado sea el del JWT (o que el rol sea profesor).
- **RNF-09** (200 MB de audios): validado en `POST /admin/palabras/:id/audio` (1 MB por archivo ya lo acota estructuralmente; monitoreo del total queda fuera del alcance del backend en esta versión).
- **RNF-12** (paginación >50 elementos): aplica a `GET /admin/palabras` y `GET /admin/alumnos(/:id)`. Sugerido: `?pagina=1&porPagina=50`.
- **RNF-13** (respaldo SQLite): fuera del alcance del código de la app — es una tarea operativa (cron de respaldo del archivo `.sqlite`) a definir con TI de NovaUniversitas, según el ERS §8.2.

## 5. Puntos que siguen abiertos (heredados del ERS, no de este documento)

Este diseño no resuelve, porque no le corresponde, los puntos que el ERS ya marca como pendientes en su §8.2 (servidor/dominio/respaldo con TI, contenido legal del aviso de privacidad, catálogo incompleto de las 45 palabras). El backlog (`backlog.md`) los reconoce como bloqueadores de ciertas tareas, no los intenta resolver.

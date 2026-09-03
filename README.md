# Spelling Bee

App móvil Flutter de NovaUniversitas para que sus estudiantes de inglés practiquen pronunciación, deletreo (spelling) y construcción de oraciones con vocabulario organizado en 3 niveles de dificultad. Backend propio en Node.js + NestJS, base de datos SQLite.

## Estructura del repo

```
.
├── docs/       Documentos fuente: ERS, diseño técnico, backlog y guía para Claude Code
├── backend/    API REST en NestJS + TypeScript
└── app/        App móvil en Flutter (Android)
```

El orden de autoridad de los documentos y las reglas de negocio del proyecto están descritos en [docs/CLAUDE.md](docs/CLAUDE.md). El plan de trabajo tarea por tarea está en [docs/backlog.md](docs/backlog.md).

## Backend (`/backend`)

Requisitos: Node.js 20+ (probado con Node v26.5.0 / npm 11).

```bash
cd backend
npm install          # instalar dependencias
npm run start:dev    # levantar en modo desarrollo (watch)
npm run build         # compilar a dist/
npm run start:prod    # ejecutar el build de producción
npm run lint          # oxlint sobre src/ y test/
npm run format         # prettier --write sobre src/ y test/
npm run test           # pruebas unitarias (vitest)
npm run test:e2e       # pruebas end-to-end (vitest)
```

## App (`/app`)

Requisitos: Flutter 3.44+ / Dart 3.12+ (canal stable), Android SDK (mínimo API 26 — RNF-06).

```bash
cd app
flutter pub get                                    # instalar dependencias
flutter run                                         # ejecutar en un dispositivo/emulador conectado
flutter analyze                                     # linter (flutter_lints)
dart format .                                       # formatear
flutter test                                        # pruebas
```

## Estado del proyecto

En desarrollo, siguiendo el backlog por fases descrito en [docs/backlog.md](docs/backlog.md). La Fase 0 (configuración inicial del monorepo) está completa; el resto de las tareas se implementan en orden, una a la vez.

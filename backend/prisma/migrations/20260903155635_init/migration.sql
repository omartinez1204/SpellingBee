-- CreateTable
CREATE TABLE "usuarios" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "nombre_usuario" TEXT NOT NULL,
    "contrasena_hash" TEXT NOT NULL,
    "rol" TEXT NOT NULL,
    "correo_electronico" TEXT NOT NULL,
    "debe_cambiar_contrasena" BOOLEAN NOT NULL DEFAULT false,
    "correo_recuperacion" TEXT,
    "fecha_registro" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "perfiles_alumno" (
    "id_usuario" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "nombre" TEXT NOT NULL,
    "apellido_paterno" TEXT NOT NULL,
    "apellido_materno" TEXT NOT NULL,
    "carrera" TEXT NOT NULL,
    "semestre" INTEGER NOT NULL,
    CONSTRAINT "perfiles_alumno_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "usuarios" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "niveles" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "nombre" TEXT NOT NULL,
    "orden" INTEGER NOT NULL
);

-- CreateTable
CREATE TABLE "palabras" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "texto" TEXT NOT NULL,
    "id_nivel" INTEGER NOT NULL,
    "significado_es" TEXT,
    "oracion_ejemplo" TEXT,
    "nombre_archivo_audio" TEXT,
    "completa" BOOLEAN NOT NULL DEFAULT false,
    "oculta" BOOLEAN NOT NULL DEFAULT false,
    "fecha_alta" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "id_profesor_autor" INTEGER NOT NULL,
    CONSTRAINT "palabras_id_nivel_fkey" FOREIGN KEY ("id_nivel") REFERENCES "niveles" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "palabras_id_profesor_autor_fkey" FOREIGN KEY ("id_profesor_autor") REFERENCES "usuarios" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "registros_practica" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "id_alumno" INTEGER NOT NULL,
    "id_palabra" INTEGER NOT NULL,
    "id_nivel_en_practica" INTEGER NOT NULL,
    "tiempo_segundos" INTEGER NOT NULL,
    "oracion_alumno" TEXT NOT NULL,
    "deletreo_correcto" BOOLEAN NOT NULL,
    "fecha_hora" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sincronizado" BOOLEAN NOT NULL,
    CONSTRAINT "registros_practica_id_alumno_fkey" FOREIGN KEY ("id_alumno") REFERENCES "usuarios" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "registros_practica_id_palabra_fkey" FOREIGN KEY ("id_palabra") REFERENCES "palabras" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "rachas" (
    "id_alumno" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "dias_consecutivos" INTEGER NOT NULL DEFAULT 0,
    "ultima_fecha_practica" DATETIME NOT NULL,
    CONSTRAINT "rachas_id_alumno_fkey" FOREIGN KEY ("id_alumno") REFERENCES "usuarios" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "usuarios_nombre_usuario_key" ON "usuarios"("nombre_usuario");

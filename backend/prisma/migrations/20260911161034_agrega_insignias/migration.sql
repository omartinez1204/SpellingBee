-- CreateTable
CREATE TABLE "insignias" (
    "id_alumno" INTEGER NOT NULL,
    "id_nivel" INTEGER NOT NULL,
    "fecha_otorgada" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY ("id_alumno", "id_nivel"),
    CONSTRAINT "insignias_id_alumno_fkey" FOREIGN KEY ("id_alumno") REFERENCES "usuarios" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "insignias_id_nivel_fkey" FOREIGN KEY ("id_nivel") REFERENCES "niveles" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

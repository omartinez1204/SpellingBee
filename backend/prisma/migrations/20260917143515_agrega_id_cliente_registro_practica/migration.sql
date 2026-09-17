-- AlterTable
ALTER TABLE "registros_practica" ADD COLUMN "id_cliente" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "registros_practica_id_cliente_key" ON "registros_practica"("id_cliente");

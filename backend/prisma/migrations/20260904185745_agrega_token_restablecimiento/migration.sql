-- AlterTable
ALTER TABLE "usuarios" ADD COLUMN "token_restablecimiento" TEXT;
ALTER TABLE "usuarios" ADD COLUMN "token_restablecimiento_expira" DATETIME;

import { defineConfig } from 'vitest/config';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    // AuthModule exige JWT_SECRET al arrancar (T-011); todo e2e-spec importa
    // AppModule tarde o temprano, así que .env se carga una vez aquí en vez
    // de que cada archivo de test tenga que acordarse de hacerlo.
    setupFiles: ['./test/setup-env.ts'],
  },
});

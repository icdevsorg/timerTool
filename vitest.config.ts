import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    testTimeout: 120_000,
    hookTimeout: 120_000,
    globals: true,
    include: ['pic/**/*.test.ts'],
    // Run test files sequentially to avoid PocketIC server conflicts
    fileParallelism: false,
    // Use forks pool to isolate each file's PocketIC server
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
  },
});

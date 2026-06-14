import type { Plugin } from 'vite';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

function metricsStubPlugin(): Plugin {
  return {
    name: 'metrics-stub',
    configureServer(server) {
      server.middlewares.use('/metrics', (_req, res) => {
        res.setHeader('Content-Type', 'text/plain');
        res.end('# frontend metrics stub\nfrontend_up 1\n');
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), metricsStubPlugin()],
  server: {
    port: 3000,
    proxy: {
      '/api': 'http://localhost:8080',
      '/metrics': 'http://localhost:8080',
      '/internal': 'http://localhost:8081',
      '/worker': 'http://localhost:8081',
    },
  },
  build: {
    outDir: 'dist',
  },
});

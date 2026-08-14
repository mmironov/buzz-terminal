import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// `npm run build` writes to dist/, which backend/firebase.json serves as the
// hosting root. The path there is relative to backend/, so moving this directory
// means editing that too.
export default defineConfig({
  plugins: [react()],
  build: { outDir: 'dist', sourcemap: true },
  server: { port: 5173, strictPort: true },
});

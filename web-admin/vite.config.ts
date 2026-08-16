import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// `npm run build` writes to dist/, which the sibling firebase.json serves as the
// hosting root.
export default defineConfig({
  plugins: [react()],
  build: { outDir: 'dist', sourcemap: true },
  server: { port: 5173, strictPort: true },
});

import { defineConfig } from 'tsup';

// Single self-executing bundle for a CDN <script>. Bundles web-core + socket.io-client;
// livekit-client stays external (chat doesn't need it; it lazy-loads only on a call).
export default defineConfig({
  entry: { widget: 'src/index.ts' },
  format: ['iife'],
  globalName: 'VoxaWidget',
  platform: 'browser',
  minify: true,
  sourcemap: true,
  clean: true,
  external: ['livekit-client'],
});

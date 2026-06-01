import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm', 'cjs'],
  dts: true,
  sourcemap: true,
  clean: true,
  treeshake: true,
  // Keep heavy media deps external (peer-installed by the host app).
  external: ['livekit-client', 'socket.io-client'],
});

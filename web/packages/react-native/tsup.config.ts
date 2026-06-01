import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm', 'cjs'],
  dts: true,
  sourcemap: true,
  clean: true,
  treeshake: true,
  external: [
    'react',
    'react-native',
    '@livekit/react-native',
    '@livekit/react-native-webrtc',
    'livekit-client',
    'socket.io-client',
    '@voxaflow/react',
    '@voxaflow/web-core',
  ],
});

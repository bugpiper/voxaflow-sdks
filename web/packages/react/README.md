# @voxaflow/react

React hooks + components for the Voxa Flow Web SDK, built on [`@voxaflow/web-core`](../web-core).

## Install

```sh
npm i @voxaflow/react @voxaflow/web-core react livekit-client socket.io-client
```

## Quick start

```tsx
import { VoxaProvider, CallView, ChatWidget } from '@voxaflow/react';

function App() {
  return (
    <VoxaProvider
      endpoint="https://voxaflow.fastwheel.ai/api"
      token={serverMintedToken}
      onTokenRefresh={() => myBackend.freshVoxaToken()}
    >
      <div style={{ height: 480 }}><CallView video /></div>
      <div style={{ height: 480 }}><ChatWidget channel="my-web-widget" /></div>
    </VoxaProvider>
  );
}
```

Or compose your own UI with the hooks:

```tsx
import { useConnectionState, useTranscript, useVoxaCall } from '@voxaflow/react';

function MyCall() {
  const conn = useConnectionState();
  const { start, end, toggleMic, micOn, call } = useVoxaCall();
  const { finals, interim } = useTranscript();
  // …render your own controls + transcript…
}
```

## API (v0)

- **`<VoxaProvider endpoint token onTokenRefresh>`** — creates + connects a `VoxaClient` once and provides it via context.
- **Hooks**: `useVoxaClient()`, `useConnectionState()`, `useTranscript()` (finals + per-speaker interim), `useVoxaCall()` (start/end/mic/camera), `useVoxaChat({ channel | conversationId })` (messages + send).
- **Components**: `<CallView/>` (controls + live transcript), `<ChatWidget/>` (threaded chat + bot, AI-transparency labeling).

Styling is intentionally light (inline) for v0 — the Midnight Intelligence design-token theme + the richer components (`<VideoRoom/>` with LiveKit tiles, `<CopilotPanel/>` with SmartForm + suggestions, `<DeviceMenu/>`, `<BackgroundPicker/>`) are the next increment. For video today, use the LiveKit room directly via `call.lkRoom`.

## Build

```sh
pnpm install
pnpm --filter @voxaflow/react build
```

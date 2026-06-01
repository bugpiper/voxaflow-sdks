# @voxaflow/widget

Embeddable, no-framework Voxa Flow chat widget — a single CDN `<script>` that mounts a floating launcher → chat panel (with AI bot). Built on [`@voxaflow/web-core`](../web-core); no React on the host page. Renders in a **Shadow DOM** so it never clashes with the host site's CSS.

## Drop-in usage

```html
<script
  src="https://cdn.voxaflow.com/widget.js"
  data-endpoint="https://voxaflow.fastwheel.ai/api"
  data-token-endpoint="https://your-app.com/api/voxa-token"
  data-channel="your-web-widget"
  data-color="#4f46e5"
  data-title="Chat with us"
></script>
```

It self-initializes: fetches a Voxa token from your `data-token-endpoint` (your backend mints a short-lived token — never an API secret), connects, and shows the launcher. The token endpoint may return JSON `{ "token": "..." }` / `{ "accessToken": "..." }` or a raw token string. `onTokenRefresh` re-fetches from the same endpoint on expiry.

### Data attributes

| Attribute | Required | Default | Notes |
|-----------|----------|---------|-------|
| `data-token-endpoint` | yes* | — | URL your backend serves a Voxa token from |
| `data-token` | yes* | — | …or a pre-fetched token (trials) |
| `data-endpoint` | no | `https://voxaflow.fastwheel.ai/api` | Voxa API base |
| `data-channel` | no | — | chat channel handle |
| `data-color` | no | `#4f46e5` | accent color |
| `data-title` | no | `Chat with us` | header title |

\* one of `data-token-endpoint` or `data-token`.

## Programmatic API

The bundle also exposes `window.VoxaWidget`:

```html
<script src="/widget.js"></script>
<script>
  const handle = await VoxaWidget.init({
    endpoint: 'https://voxaflow.fastwheel.ai/api',
    tokenEndpoint: '/api/voxa-token',
    channel: 'your-web-widget',
  });
  handle.open(); // handle.close(); handle.destroy();
</script>
```

## Build

```sh
pnpm --filter @voxaflow/widget build   # → dist/widget.global.js (IIFE)
```

`livekit-client` is **not** bundled (the chat widget doesn't need WebRTC; web-core lazy-loads it only if a call is started). Bundle ≈ 570 KB (~150 KB gzipped), dominated by `socket.io-client`.

## Status (v0)

Chat + bot (launcher, threaded panel, bot labeling, theme color, Shadow DOM). Planned: click-to-call / click-to-video buttons, i18n, richer theming/white-label, unread badge, proactive messages.

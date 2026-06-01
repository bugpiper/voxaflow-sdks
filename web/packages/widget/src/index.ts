import { VoxaClient } from '@voxaflow/web-core';
import type { ChatMessage, ChatSession, VoxaConnectionState } from '@voxaflow/web-core';

export interface WidgetConfig {
  /** Voxa API base, e.g. https://voxaflow.fastwheel.ai/api */
  endpoint: string;
  /** Tenant URL that returns a Voxa access token (JSON {token}|{accessToken} or raw text). */
  tokenEndpoint?: string;
  /** Or a pre-fetched token (e.g. for trials). */
  token?: string;
  /** Chat channel handle to start the conversation on. */
  channel?: string;
  /** Theme accent color. */
  color?: string;
  /** Header title. */
  title?: string;
}

const DEFAULTS = { endpoint: 'https://voxaflow.fastwheel.ai/api', color: '#4f46e5', title: 'Chat with us' };

// Capture our own <script> tag at load time (currentScript is reliable during sync eval).
const SELF = (typeof document !== 'undefined' ? document.currentScript : null) as HTMLScriptElement | null;

async function fetchToken(tokenEndpoint: string): Promise<string> {
  const res = await fetch(tokenEndpoint, { method: 'GET', credentials: 'include' });
  if (!res.ok) throw new Error(`token endpoint returned HTTP ${res.status}`);
  const ct = res.headers.get('content-type') ?? '';
  if (ct.includes('application/json')) {
    const j = (await res.json()) as { token?: string; accessToken?: string };
    return j.token ?? j.accessToken ?? '';
  }
  return (await res.text()).trim();
}

function configFromScript(): WidgetConfig | null {
  const el =
    SELF ?? (document.querySelector('script[data-token-endpoint],script[data-voxa-widget]') as HTMLScriptElement | null);
  if (!el) return null;
  const d = el.dataset;
  if (!d.tokenEndpoint && !d.token) return null;
  return {
    endpoint: d.endpoint ?? DEFAULTS.endpoint,
    tokenEndpoint: d.tokenEndpoint,
    token: d.token,
    channel: d.channel,
    color: d.color,
    title: d.title,
  };
}

function whenBodyReady(fn: () => void): void {
  if (document.body) fn();
  else document.addEventListener('DOMContentLoaded', fn, { once: true });
}

/** Mount the widget. Returns a handle with open/close/destroy. */
export async function init(config: WidgetConfig): Promise<{ open: () => void; close: () => void; destroy: () => void }> {
  const color = config.color ?? DEFAULTS.color;
  const title = config.title ?? DEFAULTS.title;

  const token = config.token ?? (config.tokenEndpoint ? await fetchToken(config.tokenEndpoint) : '');
  if (!token) throw new Error('VoxaWidget: a token or tokenEndpoint is required');

  const client = new VoxaClient({
    endpoint: config.endpoint,
    token,
    onTokenRefresh: config.tokenEndpoint ? () => fetchToken(config.tokenEndpoint!) : undefined,
  });

  // ── Shadow DOM UI ──────────────────────────────────────────────────────────
  const host = document.createElement('div');
  host.setAttribute('data-voxa-widget-root', '');
  const root = host.attachShadow({ mode: 'open' });
  root.innerHTML = `
    <style>
      :host { all: initial; }
      * { box-sizing: border-box; font-family: system-ui, -apple-system, sans-serif; }
      .launcher { position: fixed; right: 20px; bottom: 20px; width: 56px; height: 56px; border-radius: 50%;
        background: ${color}; color: #fff; border: none; cursor: pointer; box-shadow: 0 6px 20px rgba(0,0,0,.25);
        font-size: 24px; display: flex; align-items: center; justify-content: center; z-index: 2147483000; }
      .panel { position: fixed; right: 20px; bottom: 88px; width: 360px; max-width: calc(100vw - 40px); height: 520px;
        max-height: calc(100vh - 120px); background: #fff; border-radius: 16px; box-shadow: 0 12px 40px rgba(0,0,0,.28);
        display: none; flex-direction: column; overflow: hidden; z-index: 2147483000; }
      .panel.open { display: flex; }
      .hd { background: ${color}; color: #fff; padding: 14px 16px; font-weight: 600; display: flex; align-items: center; justify-content: space-between; }
      .hd .st { font-size: 11px; font-weight: 400; opacity: .85; }
      .x { background: none; border: none; color: #fff; font-size: 20px; cursor: pointer; line-height: 1; }
      .msgs { flex: 1; overflow-y: auto; padding: 12px; background: #f9fafb; }
      .row { display: flex; margin: 4px 0; }
      .row.me { justify-content: flex-end; }
      .bub { max-width: 78%; padding: 8px 11px; border-radius: 12px; font-size: 14px; line-height: 1.4; white-space: pre-wrap; }
      .bub.them { background: #fff; border: 1px solid #e5e7eb; color: #111827; }
      .bub.me { background: ${color}; color: #fff; }
      .bub.draft { opacity: .6; }
      .botlbl { font-size: 10px; opacity: .7; margin-bottom: 2px; }
      form { display: flex; gap: 6px; padding: 10px; border-top: 1px solid #e5e7eb; background: #fff; }
      input { flex: 1; padding: 9px 11px; border: 1px solid #d1d5db; border-radius: 10px; font-size: 14px; }
      .send { padding: 9px 14px; border: none; border-radius: 10px; background: ${color}; color: #fff; cursor: pointer; }
      .empty { color: #9ca3af; font-size: 13px; text-align: center; margin-top: 24px; }
    </style>
    <button class="launcher" aria-label="Open chat" aria-haspopup="dialog">💬</button>
    <div class="panel" role="dialog" aria-label="${title}">
      <div class="hd"><span>${title}<span class="st" id="st"> · connecting</span></span><button class="x" aria-label="Close chat">×</button></div>
      <div class="msgs" id="msgs" aria-live="polite"><div class="empty">Say hello to start the conversation.</div></div>
      <form id="f"><input id="in" placeholder="Type a message…" aria-label="Message" autocomplete="off" /><button class="send" type="submit">Send</button></form>
    </div>`;
  whenBodyReady(() => document.body.appendChild(host));

  const launcher = root.querySelector('.launcher') as HTMLButtonElement;
  const panel = root.querySelector('.panel') as HTMLElement;
  const msgs = root.querySelector('#msgs') as HTMLElement;
  const stEl = root.querySelector('#st') as HTMLElement;
  const form = root.querySelector('#f') as HTMLFormElement;
  const input = root.querySelector('#in') as HTMLInputElement;

  const open = () => {
    panel.classList.add('open');
    input.focus();
  };
  const close = () => panel.classList.remove('open');
  launcher.addEventListener('click', () => (panel.classList.contains('open') ? close() : open()));
  (root.querySelector('.x') as HTMLButtonElement).addEventListener('click', close);

  client.on('connectionState', (s: VoxaConnectionState) => {
    stEl.textContent = s === 'connected' ? '' : ` · ${s}`;
  });

  const rendered = new Set<string>();
  const addMessage = (m: ChatMessage) => {
    if (rendered.has(m.id)) return;
    rendered.add(m.id);
    const empty = msgs.querySelector('.empty');
    if (empty) empty.remove();
    const mine = m.sender === 'CONTACT';
    const row = document.createElement('div');
    row.className = `row ${mine ? 'me' : 'them'}`;
    const bub = document.createElement('div');
    bub.className = `bub ${mine ? 'me' : 'them'}${m.isDraft ? ' draft' : ''}`;
    if (m.isBot) {
      const lbl = document.createElement('div');
      lbl.className = 'botlbl';
      lbl.textContent = `🤖 Bot${m.isDraft ? ' · draft' : ''}`;
      bub.appendChild(lbl);
    }
    bub.appendChild(document.createTextNode(m.content));
    row.appendChild(bub);
    msgs.appendChild(row);
    msgs.scrollTop = msgs.scrollHeight;
  };

  let chat: ChatSession | null = null;
  await client.connect();
  chat = await client.openChat({ channel: config.channel });
  client.on('message', (m) => {
    if (chat && m.conversationId === chat.conversationId) addMessage(m);
  });

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const t = input.value.trim();
    if (!t || !chat) return;
    input.value = '';
    void chat.sendMessage(t);
  });

  const destroy = () => {
    chat?.leave();
    void client.disconnect();
    host.remove();
  };

  return { open, close, destroy };
}

// Auto-initialize from the <script data-token-endpoint=...> attributes.
if (typeof document !== 'undefined') {
  const cfg = configFromScript();
  if (cfg) void init(cfg).catch((e) => console.error('[VoxaWidget]', (e as Error).message));
}

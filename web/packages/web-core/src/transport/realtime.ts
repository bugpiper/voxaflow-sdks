import { io, type Socket } from 'socket.io-client';
import type { EventEmitter } from 'eventemitter3';
import type { VoxaEventMap } from '../events.js';
import {
  parseTranscript,
  parseEntity,
  parseFormUpdate,
  parseMessage,
  parseTyping,
  parsePresence,
  parseCallStatus,
} from '../models.js';

type J = Record<string, unknown>;

/** Wraps the Voxa realtime channel (Socket.IO at `/socket.io`). Authenticates with the
 *  token in the handshake and forwards the server event catalog onto the client emitter. */
export class VoxaRealtime {
  private socket?: Socket;
  private readonly origin: string;

  constructor(
    endpoint: string,
    private token: string,
    private readonly emitter: EventEmitter<VoxaEventMap>,
  ) {
    this.origin = new URL(endpoint).origin;
  }

  connect(): Promise<void> {
    this.emitter.emit('connectionState', 'connecting');
    const socket = io(this.origin, {
      path: '/socket.io',
      transports: ['websocket'],
      auth: { token: this.token },
      autoConnect: false,
    });
    this.socket = socket;

    socket.on('connect', () => this.emitter.emit('connectionState', 'connected'));
    socket.io.on('reconnect_attempt', () => this.emitter.emit('connectionState', 'reconnecting'));
    socket.on('disconnect', () => this.emitter.emit('connectionState', 'disconnected'));

    socket.on('transcript:update', (d: J) => this.emitter.emit('transcript', parseTranscript(d)));
    socket.on('entity:extracted', (d: J) => this.emitter.emit('entityExtracted', parseEntity(d)));
    socket.on('form:autofill', (d: J) => this.emitter.emit('formUpdate', parseFormUpdate(d)));
    socket.on('chat:message', (d: J) => this.emitter.emit('message', parseMessage(d)));
    socket.on('chat:draft', (d: J) => this.emitter.emit('message', parseMessage(d, true)));
    socket.on('chat:typing', (d: J) => this.emitter.emit('typing', parseTyping(d)));
    socket.on('presence:update', (d: J) => this.emitter.emit('presence', parsePresence(d)));
    socket.on('call:status', (d: J) => this.emitter.emit('callStatus', parseCallStatus(d)));

    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Realtime connect timed out')), 15000);
      socket.once('connect', () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once('connect_error', (err) => {
        clearTimeout(timer);
        reject(err);
      });
      socket.connect();
    });
  }

  /** Re-authenticate after a token refresh. */
  updateToken(token: string): void {
    this.token = token;
    const s = this.socket;
    if (!s) return;
    s.auth = { token };
    if (s.connected) {
      s.disconnect().connect();
    }
  }

  joinCall(callId: string): void {
    this.socket?.emit('call:join', callId);
  }
  leaveCall(callId: string): void {
    this.socket?.emit('call:leave', callId);
  }
  joinMeeting(meetingId: string): void {
    this.socket?.emit('meeting:join', meetingId);
  }
  leaveMeeting(meetingId: string): void {
    this.socket?.emit('meeting:leave', meetingId);
  }
  joinChat(conversationId: string): void {
    this.socket?.emit('chat:join', conversationId);
  }
  leaveChat(conversationId: string): void {
    this.socket?.emit('chat:leave', conversationId);
  }

  dispose(): void {
    this.socket?.removeAllListeners();
    this.socket?.disconnect();
    this.socket = undefined;
  }
}

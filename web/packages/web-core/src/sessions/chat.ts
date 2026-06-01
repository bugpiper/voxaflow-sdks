import { VoxaError } from '../errors.js';
import type { VoxaRest } from '../transport/rest.js';
import type { VoxaRealtime } from '../transport/realtime.js';

/** A chat conversation (text channel + AI bot). Subscribe to messages via the client's
 *  `message` event (filter by `conversationId`); bot messages have `isBot`/`botMeta`. */
export class ChatSession {
  private constructor(
    readonly conversationId: string,
    private readonly rest: VoxaRest,
    private readonly realtime: VoxaRealtime,
  ) {}

  static async open(opts: {
    rest: VoxaRest;
    realtime: VoxaRealtime;
    conversationId?: string;
    channel?: string;
    contactIdentifier?: string;
    language?: string;
  }): Promise<ChatSession> {
    const { rest, realtime, conversationId, channel, contactIdentifier, language } = opts;
    let convId: string;
    if (conversationId) {
      convId = conversationId;
    } else if (channel) {
      const res = await rest.post<{ conversationId: string }>(`/chat/widget/${channel}/start`, {
        ...(contactIdentifier ? { contactIdentifier } : {}),
        ...(language ? { language } : {}),
      });
      convId = res.conversationId;
    } else {
      throw new VoxaError('SERVER', 'openChat requires either a conversationId or a channel handle');
    }
    realtime.joinChat(convId);
    return new ChatSession(convId, rest, realtime);
  }

  /** Send a text message. Returns the new message id. The bot may run a turn (surfaced
   *  on the client's `message` event). */
  async sendMessage(content: string): Promise<string> {
    const res = await this.rest.post<{ id?: string }>(`/chat/conversations/${this.conversationId}/messages`, { content });
    return res.id ?? '';
  }

  async setTyping(typing: boolean): Promise<void> {
    if (typing) await this.rest.post(`/chat/conversations/${this.conversationId}/typing`);
  }

  markRead(): Promise<unknown> {
    return this.rest.post(`/chat/conversations/${this.conversationId}/read`);
  }

  leave(): void {
    this.realtime.leaveChat(this.conversationId);
  }
}

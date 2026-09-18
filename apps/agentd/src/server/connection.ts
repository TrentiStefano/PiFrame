import type { WebSocket } from 'ws';
import { ulid } from 'ulid';
import type {
  ClientMessage,
  ServerMessage,
  PcpEnvelope,
  PcpWelcomePayload,
  PcpError
} from '@pi-crust/pcp-ts';
import { parseIncoming, encode } from '@pi-crust/pcp-ts';
import { timingSafeEqualStrings } from './auth.js';

export type ConnectionState = 'authenticating' | 'ready' | 'attached' | 'closed';

export interface ConnectionOptions {
  ws: WebSocket;
  expectedToken: string;
  daemonVersion: string;
  startedAt: number;
  piInfo: { path: string; version: string; supported: boolean };
  onCommand: (conn: Connection, cmd: any) => Promise<void>;
  onAttach?: (conn: Connection, sessionId: string, lastSeq: number | null, commandId?: string) => Promise<void>;
  onDetach?: (conn: Connection, sessionId: string) => Promise<void>;
  onClose: (conn: Connection) => void;
}

export class Connection {
  public readonly id: string;
  public state: ConnectionState = 'authenticating';
  public attachedSessions = new Set<string>();

  private ws: WebSocket;
  private expectedToken: string;
  private daemonVersion: string;
  private startedAt: number;
  private piInfo: { path: string; version: string; supported: boolean };
  private onCommandCallback: (conn: Connection, cmd: any) => Promise<void>;
  private onAttachCallback?: (conn: Connection, sessionId: string, lastSeq: number | null, commandId?: string) => Promise<void>;
  private onDetachCallback?: (conn: Connection, sessionId: string) => Promise<void>;
  private onCloseCallback: (conn: Connection) => void;

  private handshakeTimer?: NodeJS.Timeout;
  private heartbeatInterval?: NodeJS.Timeout;
  private pongTimeout?: NodeJS.Timeout;

  // Bounded output queue
  private readonly maxQueueMessages = 2000;
  private readonly maxQueueBytes = 16 * 1024 * 1024; // 16 MB
  private queuedBytes = 0;
  private isDraining = false;
  private hasEmittedGapWarning = false;

  // Rate limiting (max 200 commands/sec)
  private commandTimestamps: number[] = [];

  constructor(opts: ConnectionOptions) {
    this.id = `c_${ulid()}`;
    this.ws = opts.ws;
    this.expectedToken = opts.expectedToken;
    this.daemonVersion = opts.daemonVersion;
    this.startedAt = opts.startedAt;
    this.piInfo = opts.piInfo;
    this.onCommandCallback = opts.onCommand;
    this.onAttachCallback = opts.onAttach;
    this.onDetachCallback = opts.onDetach;
    this.onCloseCallback = opts.onClose;

    this.init();
  }

  private init(): void {
    // Handshake timeout: 5 seconds
    this.handshakeTimer = setTimeout(() => {
      if (this.state === 'authenticating') {
        this.close(4001, 'Handshake timeout (no hello within 5s)');
      }
    }, 5000);

    this.ws.on('message', (data: Buffer | string) => {
      this.handleIncoming(data.toString());
    });

    this.ws.on('close', () => {
      this.cleanup();
    });

    this.ws.on('error', () => {
      this.cleanup();
    });
  }

  private handleIncoming(raw: string): void {
    const parseResult = parseIncoming(raw);
    if (!parseResult.ok) {
      this.send(parseResult.error);
      return;
    }

    const msg = parseResult.value;

    if (this.state === 'authenticating') {
      if (msg.kind !== 'hello') {
        this.close(4003, 'Expected hello frame');
        return;
      }
      this.handleHello(msg);
      return;
    }

    if ((msg as any).kind === 'ping') {
      this.send({
        protocol: 1,
        kind: 'pong',
        id: `pong_${Date.now()}`,
        ts: Date.now(),
        payload: {}
      } as any);
      return;
    }

    if (msg.kind === 'pong') {
      if (this.pongTimeout) {
        clearTimeout(this.pongTimeout);
        this.pongTimeout = undefined;
      }
      return;
    }

    if (msg.kind === 'command') {
      // Rate limiting: max 200 commands in a 1-second window
      const now = Date.now();
      this.commandTimestamps = this.commandTimestamps.filter(t => now - t < 1000);
      if (this.commandTimestamps.length >= 200) {
        this.send({
          protocol: 1,
          kind: 'error',
          id: `err_${now}`,
          ts: now,
          commandId: msg.commandId,
          type: 'error',
          payload: {
            code: 'RATE_LIMITED',
            message: 'Command rate limit exceeded (max 200/sec)'
          }
        } as PcpError);
        return;
      }
      this.commandTimestamps.push(now);

      // Handle session.attach / detach directly on connection
      if (msg.type === 'session.attach') {
        const sid = msg.sessionId;
        const lastSeq = (msg.payload as any)?.lastSeq ?? null;
        if (sid) {
          this.attachedSessions.add(sid);
          if (this.onAttachCallback) {
            void this.onAttachCallback(this, sid, lastSeq, msg.commandId);
          }
        }
      } else if (msg.type === 'session.detach') {
        const sid = msg.sessionId;
        if (sid) {
          this.attachedSessions.delete(sid);
          if (this.onDetachCallback) {
            void this.onDetachCallback(this, sid);
          }
        }
      }

      void this.onCommandCallback(this, msg);
    }
  }

  private handleHello(msg: any): void {
    if (this.handshakeTimer) {
      clearTimeout(this.handshakeTimer);
      this.handshakeTimer = undefined;
    }

    const token = msg.payload?.token;
    if (!token || !timingSafeEqualStrings(token, this.expectedToken)) {
      this.close(4003, 'Authentication failed');
      return;
    }

    this.state = 'ready';

    // Start 15s application heartbeat
    this.startHeartbeat();

    // Send welcome frame
    const welcomePayload: PcpWelcomePayload = {
      clientId: this.id,
      daemon: {
        version: this.daemonVersion,
        startedAt: this.startedAt,
        pid: process.pid
      },
      pi: this.piInfo,
      capabilities: ['replay.v1', 'ui.claim.v1', 'workspace.v1'],
      limits: {
        maxFrameBytes: 4 * 1024 * 1024,
        journalMaxEvents: 2000
      }
    };

    this.send({
      protocol: 1,
      kind: 'welcome',
      id: `wlc_${ulid()}`,
      ts: Date.now(),
      type: 'connection.welcome',
      payload: welcomePayload
    });
  }

  private startHeartbeat(): void {
    this.heartbeatInterval = setInterval(() => {
      if (this.state === 'closed') return;

      this.send({
        protocol: 1,
        kind: 'ping',
        id: `png_${ulid()}`,
        ts: Date.now(),
        type: 'heartbeat.ping',
        payload: {}
      });

      this.pongTimeout = setTimeout(() => {
        this.close(4008, 'Heartbeat timeout: no pong received within 10s');
      }, 10000);
    }, 15000);
  }

  public send(msg: ServerMessage | PcpEnvelope<any>): boolean {
    if (this.state === 'closed' || this.ws.readyState !== 1) {
      return false;
    }

    const serialized = encode(msg as any);
    const byteLength = Buffer.byteLength(serialized);

    // Check backpressure buffer
    if (this.queuedBytes + byteLength > this.maxQueueBytes * 2) {
      // Exceeded double threshold -> terminate slow client
      this.close(4009, 'Client too slow (backpressure buffer exceeded 32MB)');
      return false;
    }

    if (this.queuedBytes + byteLength > this.maxQueueBytes) {
      // Exceeded single threshold -> drop delta events, signal gap
      if (!this.hasEmittedGapWarning && msg.kind === 'event') {
        this.hasEmittedGapWarning = true;
        this.send({
          protocol: 1,
          kind: 'event',
          id: `gap_${ulid()}`,
          ts: Date.now(),
          sessionId: (msg as any).sessionId || '@daemon',
          seq: (msg as any).seq || 0,
          type: 'journal.gap',
          payload: { reason: 'Client buffer overrun: re-attach required' }
        });
      }
      if (msg.kind === 'event' && (msg.type.endsWith('.delta') || msg.type.endsWith('.progress'))) {
        return false; // Drop non-essential delta during congestion
      }
    } else {
      this.hasEmittedGapWarning = false;
    }

    this.queuedBytes += byteLength;
    this.ws.send(serialized, () => {
      this.queuedBytes -= byteLength;
    });

    return true;
  }

  public close(code: number, reason: string): void {
    if (this.state === 'closed') return;
    this.state = 'closed';
    try {
      this.ws.close(code, reason);
    } catch {}
    this.cleanup();
  }

  private cleanup(): void {
    this.state = 'closed';
    if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
    if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
    if (this.pongTimeout) clearTimeout(this.pongTimeout);
    this.onCloseCallback(this);
  }
}

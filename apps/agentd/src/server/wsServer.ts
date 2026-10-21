import type * as http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { Connection } from './connection.js';
import { isLoopbackHost, isOriginAllowed, hasProxyHeaders } from './origin.js';
import type { DaemonConfig } from '../config/config.js';
import type { RemoteManager } from '../remote/RemoteManager.js';
import type { ServerMessage, PcpEnvelope } from '@piframe/pcp-ts';

export interface WsServerOptions {
  httpServer: http.Server;
  remoteHttpServer?: http.Server;
  config: DaemonConfig;
  token: string;
  version: string;
  startedAt: number;
  piInfo: { path: string; version: string; supported: boolean };
  port: number;
  remoteManager?: RemoteManager;
  onCommand: (conn: Connection, cmd: any) => Promise<void>;
  onAttach?: (conn: Connection, sessionId: string, lastSeq: number | null, commandId?: string) => Promise<void>;
  onDetach?: (conn: Connection, sessionId: string) => Promise<void>;
}

export class ConnectionManager {
  private connections = new Map<string, Connection>();

  public add(conn: Connection): void {
    this.connections.set(conn.id, conn);
  }

  public remove(conn: Connection): void {
    this.connections.delete(conn.id);
  }

  public get(id: string): Connection | undefined {
    return this.connections.get(id);
  }

  public getAll(): Connection[] {
    return Array.from(this.connections.values());
  }

  public broadcast(sessionId: string, msg: ServerMessage | PcpEnvelope<any>): void {
    for (const conn of this.connections.values()) {
      if ((conn.state === 'ready' || conn.state === 'attached') &&
          (sessionId === '@daemon' || conn.attachedSessions.has(sessionId))) {
        conn.send(msg);
      }
    }
  }

  /** Broadcast ONLY to genuine local connections (never to remote devices). */
  public broadcastLocal(sessionId: string, msg: ServerMessage | PcpEnvelope<any>): void {
    for (const conn of this.connections.values()) {
      if (!conn.isRemote &&
          (conn.state === 'ready' || conn.state === 'attached') &&
          (sessionId === '@daemon' || conn.attachedSessions.has(sessionId))) {
        conn.send(msg);
      }
    }
  }

  public broadcastAll(msg: ServerMessage | PcpEnvelope<any>): void {
    for (const conn of this.connections.values()) {
      if (conn.state === 'ready' || conn.state === 'attached') conn.send(msg);
    }
  }

  public closeDevice(deviceId: string, code: number, reason: string): void {
    for (const conn of this.connections.values()) {
      if (conn.deviceId === deviceId) {
        conn.close(code, reason);
      }
    }
  }

  public closeRemote(code: number, reason: string): void {
    for (const conn of this.connections.values()) {
      if (conn.isRemote) {
        conn.close(code, reason);
      }
    }
  }

  public closeAll(code: number, reason: string): void {
    for (const conn of this.connections.values()) {
      conn.close(code, reason);
    }
    this.connections.clear();
  }
}

interface SocketUpgradeMetadata {
  viaRemoteListener: boolean;
  clientIp: string;
  rateLimitKey: string;
}

export function createWsServer(opts: WsServerOptions): { wss: WebSocketServer; manager: ConnectionManager } {
  const {
    httpServer,
    remoteHttpServer,
    config,
    token,
    version,
    startedAt,
    piInfo,
    port,
    remoteManager,
    onCommand,
    onAttach,
    onDetach
  } = opts;

  const manager = new ConnectionManager();
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4 * 1024 * 1024 });

  // ---------------------------------------------------------------------------
  // Remote lifecycle events
  // ---------------------------------------------------------------------------
  if (remoteManager) {
    remoteManager.on('deviceRevoked', (deviceId: string) => {
      manager.closeDevice(deviceId, 4003, 'Device Revoked');
    });

    remoteManager.on('allDevicesRevoked', () => {
      manager.closeRemote(4003, 'All remote devices revoked');
    });

    remoteManager.on('stopped', () => {
      manager.closeRemote(4003, 'Remote access stopped');
    });

    remoteManager.on('tunnelDown', () => {
      manager.closeRemote(4003, 'Remote tunnel connection lost');
    });

    remoteManager.on('deviceModeChanged', ({ deviceId, mode }) => {
      for (const conn of manager.getAll()) {
        if (conn.deviceId === deviceId) {
          conn.deviceMode = mode;
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Rate-limiting failed hellos (separate buckets for local and remote)
  // ---------------------------------------------------------------------------
  const failedHelloPerKey = new Map<string, number[]>();

  function isRateLimited(key: string): boolean {
    const now = Date.now();
    const attempts = (failedHelloPerKey.get(key) || []).filter((t) => now - t < 60_000);
    failedHelloPerKey.set(key, attempts);
    return attempts.length >= 20;
  }

  function recordFailedHello(key: string): void {
    const now = Date.now();
    const attempts = (failedHelloPerKey.get(key) || []).filter((t) => now - t < 60_000);
    attempts.push(now);
    failedHelloPerKey.set(key, attempts);
  }

  // Periodic pruning of the rate limit map
  const pruneTimer = setInterval(() => {
    const now = Date.now();
    for (const [key, timestamps] of failedHelloPerKey) {
      const active = timestamps.filter((t) => now - t < 60_000);
      if (active.length === 0) {
        failedHelloPerKey.delete(key);
      } else {
        failedHelloPerKey.set(key, active);
      }
    }
  }, 60_000);
  pruneTimer.unref?.();

  // Concurrency cap on unauthenticated connections arriving over remote listener
  let remoteAuthenticatingCount = 0;
  const MAX_REMOTE_AUTHENTICATING = 10;

  const upgradeMetadata = new WeakMap<WebSocket, SocketUpgradeMetadata>();

  // ---------------------------------------------------------------------------
  // Attach upgrade handlers
  // ---------------------------------------------------------------------------
  function attachUpgrade(server: http.Server, isRemoteListener: boolean): void {
    server.on('upgrade', (req, socket, head) => {
      if (isRemoteListener) {
        // Must pass remote host check
        if (!remoteManager || !remoteManager.isRemoteHostAllowed(req.headers.host)) {
          socket.write('HTTP/1.1 403 Forbidden (Untrusted Host)\r\n\r\n');
          socket.destroy();
          return;
        }

        // Must pass origin check if Origin is sent
        if (req.headers.origin && !remoteManager.isRemoteOriginAllowed(req.headers.origin)) {
          socket.write('HTTP/1.1 403 Forbidden (Untrusted Origin)\r\n\r\n');
          socket.destroy();
          return;
        }

        const clientIp = remoteManager.getTrustedClientIp(req);
        const rateLimitKey = `r:${clientIp}`;

        if (isRateLimited(rateLimitKey)) {
          socket.write('HTTP/1.1 429 Too Many Requests\r\n\r\n');
          socket.destroy();
          return;
        }

        if (remoteAuthenticatingCount >= MAX_REMOTE_AUTHENTICATING) {
          socket.write('HTTP/1.1 503 Service Unavailable (Auth Queue Busy)\r\n\r\n');
          socket.destroy();
          return;
        }

        remoteAuthenticatingCount++;
        wss.handleUpgrade(req, socket, head, (ws) => {
          upgradeMetadata.set(ws, { viaRemoteListener: true, clientIp, rateLimitKey });
          wss.emit('connection', ws, req);
        });
      } else {
        // Local loopback listener
        const localPort = req.socket.localPort || port;
        if (!isLoopbackHost(req.headers.host, localPort)) {
          socket.write('HTTP/1.1 403 Forbidden (Local listener requires loopback host)\r\n\r\n');
          socket.destroy();
          return;
        }

        if (hasProxyHeaders(req)) {
          socket.write('HTTP/1.1 403 Forbidden (Proxy headers forbidden)\r\n\r\n');
          socket.destroy();
          return;
        }

        if (!isOriginAllowed(req.headers.origin, config.web?.origins || [], localPort)) {
          socket.write('HTTP/1.1 403 Forbidden (Untrusted Origin)\r\n\r\n');
          socket.destroy();
          return;
        }

        const socketIp = req.socket.remoteAddress || '127.0.0.1';
        const rateLimitKey = `l:${socketIp}`;

        if (isRateLimited(rateLimitKey)) {
          socket.write('HTTP/1.1 429 Too Many Requests\r\n\r\n');
          socket.destroy();
          return;
        }

        wss.handleUpgrade(req, socket, head, (ws) => {
          upgradeMetadata.set(ws, { viaRemoteListener: false, clientIp: socketIp, rateLimitKey });
          wss.emit('connection', ws, req);
        });
      }
    });
  }

  attachUpgrade(httpServer, false);
  if (remoteHttpServer) {
    attachUpgrade(remoteHttpServer, true);
  }

  // ---------------------------------------------------------------------------
  // WebSocket Connection Handler
  // ---------------------------------------------------------------------------
  wss.on('connection', (ws: WebSocket, _req: http.IncomingMessage) => {
    const meta = upgradeMetadata.get(ws) || {
      viaRemoteListener: false,
      clientIp: 'unknown',
      rateLimitKey: 'l:unknown'
    };

    let decrementedAuthQueue = false;
    const releaseAuthSlot = () => {
      if (meta.viaRemoteListener && !decrementedAuthQueue) {
        decrementedAuthQueue = true;
        remoteAuthenticatingCount = Math.max(0, remoteAuthenticatingCount - 1);
      }
    };

    const conn = new Connection({
      ws,
      expectedToken: token,
      daemonVersion: version,
      startedAt,
      piInfo,
      remoteManager,
      viaRemoteListener: meta.viaRemoteListener,
      clientIp: meta.clientIp,
      onCommand,
      onAttach,
      onDetach,
      onClose: (closedConn) => {
        releaseAuthSlot();
        if (closedConn.authFailed) {
          recordFailedHello(meta.rateLimitKey);
        }
        for (const sessionId of closedConn.attachedSessions) {
          void onDetach?.(closedConn, sessionId).catch(() => {});
        }
        manager.remove(closedConn);
      }
    });

    // When connection transitions to ready, release authenticating slot
    const checkReadyInterval = setInterval(() => {
      if (conn.state !== 'authenticating') {
        releaseAuthSlot();
        clearInterval(checkReadyInterval);
      }
    }, 100);
    checkReadyInterval.unref?.();

    manager.add(conn);
  });

  return { wss, manager };
}

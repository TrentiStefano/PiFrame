import type * as http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { Connection } from './connection.js';
import { isOriginAllowed } from './origin.js';
import type { DaemonConfig } from '../config/config.js';
import type { ServerMessage, PcpEnvelope } from '@pi-crust/pcp-ts';

export interface WsServerOptions {
  httpServer: http.Server;
  config: DaemonConfig;
  token: string;
  version: string;
  startedAt: number;
  piInfo: { path: string; version: string; supported: boolean };
  port: number;
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

  public broadcastAll(msg: ServerMessage | PcpEnvelope<any>): void {
    for (const conn of this.connections.values()) {
      if (conn.state === 'ready' || conn.state === 'attached') conn.send(msg);
    }
  }

  public closeAll(code: number, reason: string): void {
    for (const conn of this.connections.values()) {
      conn.close(code, reason);
    }
    this.connections.clear();
  }
}

export function createWsServer(opts: WsServerOptions): { wss: WebSocketServer; manager: ConnectionManager } {
  const { httpServer, config, token, version, startedAt, piInfo, port, onCommand, onAttach, onDetach } = opts;
  const manager = new ConnectionManager();
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4 * 1024 * 1024 });

  // Rate limiting failed hellos per IP: max 20 / min
  const failedHelloPerIp = new Map<string, number[]>();

  function isIpRateLimited(ip: string): boolean {
    const now = Date.now();
    const attempts = (failedHelloPerIp.get(ip) || []).filter(t => now - t < 60_000);
    failedHelloPerIp.set(ip, attempts);
    return attempts.length >= 20;
  }

  function recordFailedHello(ip: string): void {
    const now = Date.now();
    const attempts = (failedHelloPerIp.get(ip) || []).filter(t => now - t < 60_000);
    attempts.push(now);
    failedHelloPerIp.set(ip, attempts);
  }

  httpServer.on('upgrade', (req, socket, head) => {
    const ip = req.socket.remoteAddress || 'unknown';

    if (isIpRateLimited(ip)) {
      socket.write('HTTP/1.1 429 Too Many Requests\r\n\r\n');
      socket.destroy();
      return;
    }

    const origin = req.headers.origin;
    if (!isOriginAllowed(origin, config.web?.origins || [], port)) {
      socket.write('HTTP/1.1 403 Forbidden (Origin rejected)\r\n\r\n');
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit('connection', ws, req);
    });
  });

  wss.on('connection', (ws: WebSocket, req: http.IncomingMessage) => {
    const ip = req.socket.remoteAddress || 'unknown';

    const conn = new Connection({
      ws,
      expectedToken: token,
      daemonVersion: version,
      startedAt,
      piInfo,
      onCommand,
      onAttach,
      onDetach,
      onClose: (closedConn) => {
        if (!closedConn.authenticated) {
          recordFailedHello(ip);
        }
        for (const sessionId of closedConn.attachedSessions) {
          void onDetach?.(closedConn, sessionId).catch(() => {});
        }
        manager.remove(closedConn);
      }
    });

    manager.add(conn);
  });

  return { wss, manager };
}

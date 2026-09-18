import { WebSocketServer, WebSocket } from 'ws';
import * as http from 'node:http';

export interface FaultProxyConfig {
  targetPort: number;
  dropAfterMs?: number;
  dropAfterFrames?: number;
  duplicateFrames?: boolean;
  latencyMs?: number;
  corruptEveryNFrames?: number;
}

export class FaultProxy {
  private server: http.Server;
  private wss: WebSocketServer;
  private config: FaultProxyConfig;
  private frameCount = 0;
  private activeSockets = new Set<WebSocket>();

  constructor(config: FaultProxyConfig) {
    this.config = config;
    this.server = http.createServer();
    this.wss = new WebSocketServer({ server: this.server });

    this.wss.on('connection', (clientWs, req) => {
      this.activeSockets.add(clientWs);

      const targetUrl = `ws://127.0.0.1:${this.config.targetPort}${req.url || ''}`;
      const upstreamWs = new WebSocket(targetUrl);
      this.activeSockets.add(upstreamWs);

      const clientQueue: { data: any; isBinary: boolean }[] = [];
      let upstreamOpen = false;

      upstreamWs.on('open', () => {
        upstreamOpen = true;
        while (clientQueue.length > 0) {
          const item = clientQueue.shift()!;
          if (upstreamWs.readyState === WebSocket.OPEN) {
            upstreamWs.send(item.data, { binary: item.isBinary });
          }
        }
      });

      // If dropAfterMs configured, set a timeout to drop abruptly
      let dropTimer: NodeJS.Timeout | null = null;
      if (this.config.dropAfterMs) {
        dropTimer = setTimeout(() => {
          clientWs.terminate();
          upstreamWs.terminate();
        }, this.config.dropAfterMs);
      }

      // Forward client -> upstream
      clientWs.on('message', (data, isBinary) => {
        if (upstreamOpen && upstreamWs.readyState === WebSocket.OPEN) {
          upstreamWs.send(data, { binary: isBinary });
        } else {
          clientQueue.push({ data, isBinary });
        }
      });

      // Forward upstream -> client with fault injection
      upstreamWs.on('message', async (data, isBinary) => {
        this.frameCount++;

        // 1. Check frame drop
        if (this.config.dropAfterFrames && this.frameCount >= this.config.dropAfterFrames) {
          clientWs.terminate();
          upstreamWs.terminate();
          return;
        }

        // 2. Check latency
        if (this.config.latencyMs) {
          await new Promise((resolve) => setTimeout(resolve, this.config.latencyMs));
        }

        if (clientWs.readyState !== WebSocket.OPEN) return;

        // 3. Check frame corruption
        if (
          this.config.corruptEveryNFrames &&
          this.frameCount % this.config.corruptEveryNFrames === 0
        ) {
          clientWs.send('{"protocol":1,"kind":"event","truncated":true', { binary: isBinary });
          return;
        }

        // 4. Normal send
        clientWs.send(data, { binary: isBinary });

        // 5. Check duplicate
        if (this.config.duplicateFrames && clientWs.readyState === WebSocket.OPEN) {
          clientWs.send(data, { binary: isBinary });
        }
      });

      clientWs.on('close', () => {
        if (dropTimer) clearTimeout(dropTimer);
        this.activeSockets.delete(clientWs);
        upstreamWs.close();
      });

      upstreamWs.on('close', () => {
        if (dropTimer) clearTimeout(dropTimer);
        this.activeSockets.delete(upstreamWs);
        clientWs.close();
      });

      clientWs.on('error', () => {
        upstreamWs.terminate();
      });

      upstreamWs.on('error', (err) => {
        console.error('UPSTREAM ERROR:', err);
        clientWs.terminate();
      });
    });
  }

  public async start(): Promise<number> {
    return new Promise((resolve, reject) => {
      this.server.listen(0, '127.0.0.1', () => {
        const addr = this.server.address() as any;
        resolve(addr.port);
      });
      this.server.on('error', reject);
    });
  }

  public async close(): Promise<void> {
    for (const ws of this.activeSockets) {
      try {
        ws.terminate();
      } catch {}
    }
    this.activeSockets.clear();

    await new Promise<void>((resolve) => {
      this.wss.close(() => resolve());
    });

    await new Promise<void>((resolve) => {
      this.server.close(() => resolve());
    });
  }
}

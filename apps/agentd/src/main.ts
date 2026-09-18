import * as http from 'node:http';
import { acquireSingleInstanceLock } from './config/lock.js';
import { loadConfig } from './config/config.js';
import { generateAndSaveToken, writeRuntimeInfo, cleanupRuntimeFiles } from './config/runtime.js';
import { discoverPi } from './pi/discovery.js';
import { probeCapabilities } from './pi/capabilities.js';
import { createHttpServer } from './server/httpServer.js';
import { createWsServer } from './server/wsServer.js';
import { SessionRegistry } from './sessions/SessionRegistry.js';
import { Dispatcher } from './commands/Dispatcher.js';

const VERSION = '0.1.0';

async function main() {
  console.log(`[agentd] Starting Pi-Crust Daemon v${VERSION}...`);

  // 1. Single-instance mutex lock
  const lockHandle = acquireSingleInstanceLock();
  if (!lockHandle) {
    console.log('[agentd] Another healthy daemon instance is already active. Exiting 0.');
    process.exit(0);
  }

  // 2. Load configuration
  const config = loadConfig();

  // 3. Discover Pi installation and capabilities
  const piInstall = await discoverPi(config.piPath);
  console.log(`[agentd] Pi discovery result: found=${piInstall.found}, version=${piInstall.version || 'none'}, supported=${piInstall.supported}`);
  if (piInstall.path) {
    console.log(`[agentd] Using Pi executable: ${piInstall.path}`);
  }

  const piCaps = piInstall.path
    ? await probeCapabilities(piInstall.path, piInstall.version || '0.85.0', piInstall.supported)
    : {
        version: '0.0.0',
        supported: false,
        modes: [],
        features: []
      };

  const startedAt = Date.now();

  let token = '';
  let port = 0;

  // Read cli args for optional --port
  const portArgIdx = process.argv.indexOf('--port');
  if (portArgIdx !== -1 && process.argv[portArgIdx + 1]) {
    port = parseInt(process.argv[portArgIdx + 1], 10) || 0;
  }

  // Prepare HTTP server instance
  let httpServer: http.Server;
  let registry: SessionRegistry;
  let dispatcher: Dispatcher;

  httpServer = createHttpServer({
    config,
    token: () => token,
    version: VERSION,
    startedAt
  });

  // Bind exclusively to 127.0.0.1 (loopback)
  await new Promise<void>((resolve, reject) => {
    httpServer.listen(port, '127.0.0.1', () => {
      resolve();
    });
    httpServer.on('error', reject);
  });

  const boundAddr = httpServer.address() as any;
  const actualPort = boundAddr.port;
  console.log(`[agentd] HTTP/WS server bound strictly to 127.0.0.1:${actualPort}`);

  // 5. Initialize runtime directory (~/.pi-crust/runtime/daemon.json, daemon.token, etc.)
  token = generateAndSaveToken();
  writeRuntimeInfo({
    port: actualPort,
    pid: process.pid,
    version: VERSION,
    startedAt,
    protocol: 1
  });

  // 6. Setup WebSocket Server, SessionRegistry and Dispatcher
  let isShuttingDown = false;

  const { wss, manager } = createWsServer({
    httpServer,
    config,
    token,
    version: VERSION,
    startedAt,
    piInfo: {
      path: piInstall.path || '',
      version: piInstall.version || '',
      supported: piInstall.supported
    },
    port: actualPort,
    onCommand: async (conn, cmd) => {
      await dispatcher.handle(conn, cmd);
    },
    onAttach: async (conn, sessionId, lastSeq) => {
      await registry.attachClient(sessionId, conn, lastSeq);
    },
    onDetach: async (conn, sessionId) => {
      await registry.detachClient(sessionId, conn);
    }
  });

  registry = new SessionRegistry({
    piExecutablePath: piInstall.path || '',
    capabilities: piCaps,
    workerIdleTimeoutMs: config.workerIdleTimeoutMs,
    connectionManager: manager
  });

  dispatcher = new Dispatcher(registry, manager);

  console.log(`[agentd] Ready. Listening on ws://127.0.0.1:${actualPort}`);

  // 7. Clean graceful shutdown on SIGINT / SIGTERM
  const shutdown = async (signal: string) => {
    if (isShuttingDown) return;
    isShuttingDown = true;
    console.log(`[agentd] Received ${signal}. Draining and shutting down...`);

    // 1. Notify clients with close code 4010 (Daemon in shutdown)
    manager.closeAll(4010, 'Daemon shutting down');

    // 2. Stop workers gracefully
    await registry.closeAll(3000);

    // 3. Close HTTP/WS server
    await new Promise<void>((resolve) => {
      httpServer.close(() => resolve());
    });

    // 4. Cleanup runtime files & single instance lock
    cleanupRuntimeFiles();
    lockHandle.release();

    console.log('[agentd] Shutdown complete.');
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('[agentd] Fatal error during startup:', err);
  process.exit(1);
});

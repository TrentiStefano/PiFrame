import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const agentdRequire = createRequire(path.join(root, 'apps/agentd/package.json'));
const WebSocket = agentdRequire('ws');
const home = mkdtempSync(path.join(os.tmpdir(), 'pi-crust-bundle-smoke-'));
const bundlePath = path.join(root, 'apps/agentd/dist/pi-agentd.cjs');
const child = spawn(process.execPath, [bundlePath, '--port', '0'], {
  cwd: root,
  env: { ...process.env, PI_CRUST_HOME: home },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let logs = '';
child.stdout.setEncoding('utf8').on('data', (chunk) => { logs += chunk; });
child.stderr.setEncoding('utf8').on('data', (chunk) => { logs += chunk; });

const waitUntil = async (predicate, timeoutMs = 10000) => {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    if (predicate()) return;
    if (child.exitCode !== null) throw new Error(`Bundled agentd exited ${child.exitCode}: ${logs}`);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Timed out waiting for bundled agentd: ${logs}`);
};

let socket;
try {
  const runtimePath = path.join(home, 'runtime', 'daemon.json');
  await waitUntil(() => existsSync(runtimePath));
  const runtime = JSON.parse(readFileSync(runtimePath, 'utf8'));
  const token = readFileSync(path.join(home, 'runtime', 'daemon.token'), 'utf8').trim();
  socket = new WebSocket(`ws://127.0.0.1:${runtime.port}`);
  await new Promise((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  const messages = [];
  socket.on('message', (raw) => messages.push(JSON.parse(raw.toString())));
  const waitFor = async (predicate) => {
    await waitUntil(() => messages.some(predicate));
    return messages.find(predicate);
  };

  socket.send(JSON.stringify({
    protocol: 1,
    kind: 'hello',
    id: 'smoke_hello',
    ts: Date.now(),
    type: 'connection.hello',
    payload: { token, client: { name: 'bundle-smoke', version: '0.1.0' }, encoding: 'json', capabilities: [] },
  }));
  await waitFor((message) => message.kind === 'welcome');

  const commandId = 'smoke_workspace_list_files';
  socket.send(JSON.stringify({
    protocol: 1,
    kind: 'command',
    id: 'smoke_workspace_list_files_message',
    ts: Date.now(),
    commandId,
    type: 'workspace.listFiles',
    payload: {},
  }));
  const result = await waitFor((message) => message.kind === 'result' && message.commandId === commandId);
  assert.equal(result.payload.state, 'rejected');
  assert.match(result.payload.error, /sessionId is required/i);
  assert.doesNotMatch(result.payload.error, /unsupported command type/i);
  console.log('OK: bundled agentd dispatches workspace.listFiles and enforces session scope');
} finally {
  if (socket && socket.readyState !== WebSocket.CLOSED) socket.close();
  if (child.exitCode === null) {
    child.kill('SIGTERM');
    await Promise.race([
      new Promise((resolve) => child.once('exit', resolve)),
      new Promise((resolve) => setTimeout(resolve, 5000)),
    ]);
  }
  rmSync(home, { recursive: true, force: true });
}

import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { StdioPiTransport } from '../StdioPiTransport.js';
import { resolvePiLaunch } from '../executable.js';

const temporaryDirectories: string[] = [];
function fixture(source: string): string {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-transport-test-'));
  temporaryDirectories.push(directory);
  const file = path.join(directory, 'fixture.cjs');
  fs.writeFileSync(file, source);
  return file;
}

test.after(() => {
  for (const directory of temporaryDirectories) fs.rmSync(directory, { recursive: true, force: true });
});

function responderFixture(): string {
  return fixture(`
    let buffer = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => {
      buffer += chunk;
      while (buffer.includes('\\n')) {
        const index = buffer.indexOf('\\n');
        const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
        const request = JSON.parse(line);
        if (request.type === 'extension_ui_response') {
          process.stdout.write(JSON.stringify({ type: 'ui_received', request }) + '\\n');
        } else if (request.type === 'exit_now') {
          process.exit(7);
        } else {
          process.stdout.write(JSON.stringify({
            id: request.id, type: 'response', command: request.type,
            success: request.type !== 'fail', error: 'deliberate failure', data: { request }
          }) + '\\n');
        }
      }
    });
  `);
}

async function nextEvent(transport: StdioPiTransport, type: string): Promise<any> {
  for await (const event of transport.events()) if (event.type === type) return event;
  throw new Error(`Missing event ${type}`);
}

test('StdioPiTransport sends canonical flat RPC and clears both correlation queues', async () => {
  const transport = new StdioPiTransport({ executablePath: responderFixture() });
  await transport.start({ cwd: process.cwd() });
  const response = await transport.send({ command: 'get_state', arguments: { selection: 'flat' } });
  assert.equal(response.success, true);
  assert.equal(response.data.request.type, 'get_state');
  assert.deepEqual(response.data.request.selection, 'flat');
  assert.equal(response.data.request.command, undefined);
  assert.equal(response.data.request.arguments, undefined);
  assert.ok(response.data.request.id);
  assert.equal((transport as any).pendingCommands.size, 0);
  assert.equal((transport as any).fifoPendingCommands.length, 0);
  await transport.stop({ graceMs: 1000 });
});

test('StdioPiTransport rejects unsuccessful RPC responses', async () => {
  const transport = new StdioPiTransport({ executablePath: responderFixture() });
  await transport.start({ cwd: process.cwd() });
  await assert.rejects(transport.send({ command: 'fail' }), /deliberate failure/);
  assert.equal((transport as any).pendingCommands.size, 0);
  assert.equal((transport as any).fifoPendingCommands.length, 0);
  await transport.stop({ graceMs: 1000 });
});

test('StdioPiTransport sends UI response request id and does not await an RPC response', async () => {
  const transport = new StdioPiTransport({ executablePath: responderFixture() });
  await transport.start({ cwd: process.cwd() });
  const response = await transport.send({
    command: 'extension_ui_response',
    arguments: { id: 'ui-request-123', value: 'accepted' }
  });
  assert.equal(response.success, true);
  assert.equal(response.id, 'ui-request-123');
  const event = await nextEvent(transport, 'ui_received');
  assert.equal(event.request.id, 'ui-request-123');
  assert.equal(event.request.type, 'extension_ui_response');
  assert.equal(event.request.value, 'accepted');
  assert.equal((transport as any).pendingCommands.size, 0);
  assert.equal((transport as any).fifoPendingCommands.length, 0);
  await transport.stop({ graceMs: 1000 });
});

test('StdioPiTransport rejects startup failure and all pending work when child exits', async () => {
  const missing = new StdioPiTransport({ executablePath: path.join(os.tmpdir(), 'no-such-pi-executable') });
  await assert.rejects(missing.start({ cwd: process.cwd() }));
  assert.equal(missing.health().alive, false);

  const transport = new StdioPiTransport({ executablePath: responderFixture() });
  await transport.start({ cwd: process.cwd() });
  const pending = transport.send({ command: 'exit_now' });
  await assert.rejects(pending, /exited/);
  assert.equal((transport as any).pendingCommands.size, 0);
  assert.equal((transport as any).fifoPendingCommands.length, 0);
});

test('StdioPiTransport does not correlate late explicit IDs to another command', async () => {
  const transport = new StdioPiTransport({ executablePath: responderFixture() });
  await transport.start({ cwd: process.cwd() });
  // Simulate a timed-out request A and a still-pending same-type request B.
  let settled = false;
  const entry = { resolve: () => { settled = true; }, reject: () => {}, command: 'get_state' };
  (transport as any).pendingCommands.set('B', entry);
  (transport as any).fifoPendingCommands.push({ id: 'B', ...entry });
  (transport as any).handleIncomingObject({ type: 'response', id: 'A', command: 'get_state', success: true });
  assert.equal(settled, false);
  (transport as any).handleIncomingObject({ type: 'response', id: 'B', command: 'get_state', success: true });
  assert.equal(settled, true);
  await transport.stop({ graceMs: 1000 });
});

test('resolvePiLaunch handles JS module paths and Windows npm .cmd shims without a shell', () => {
  for (const extension of ['js', 'cjs', 'mjs']) {
    const result = resolvePiLaunch(`/tmp/pi.${extension}`, ['--version'], 'win32');
    assert.equal(result.file, process.execPath);
    assert.deepEqual(result.args, [`/tmp/pi.${extension}`, '--version']);
  }

  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-shim-test-'));
  temporaryDirectories.push(directory);
  const shim = path.join(directory, 'pi.cmd');
  const cli = path.join(directory, 'node_modules', '@earendil-works', 'pi-coding-agent', 'dist', 'bundle', 'cli.js');
  fs.mkdirSync(path.dirname(cli), { recursive: true });
  fs.writeFileSync(cli, '');
  const result = resolvePiLaunch(shim, ['--mode', 'rpc'], 'win32');
  assert.equal(result.file, process.execPath);
  assert.deepEqual(result.args, [cli, '--mode', 'rpc']);
});

function slowFixture(): string {
  return fixture(`
    let buffer = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => {
      buffer += chunk;
      while (buffer.includes('\\n')) {
        const index = buffer.indexOf('\\n');
        const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
        const request = JSON.parse(line);
        setTimeout(() => process.stdout.write(JSON.stringify({
          id: request.id, type: 'response', command: request.type,
          success: request.message !== 'bad', error: 'late rejection', data: {}
        }) + '\\n'), 300);
      }
    });
  `);
}

test('StdioPiTransport treats a slow prompt acknowledgement as accepted, not as a delivery failure', async () => {
  const transport = new StdioPiTransport({ executablePath: slowFixture(), commandTimeoutMs: 80 });
  await transport.start({ cwd: process.cwd() });
  const response = await transport.send({ command: 'prompt', arguments: { message: 'hello' } });
  assert.equal(response.success, true);
  assert.equal(response.data.disposition, 'pending');
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.equal((transport as any).pendingCommands.size, 0);
  assert.equal((transport as any).fifoPendingCommands.length, 0);
  await transport.stop({ graceMs: 1000 });
});

test('StdioPiTransport reports a late prompt rejection as a diagnostic', async () => {
  const transport = new StdioPiTransport({ executablePath: slowFixture(), commandTimeoutMs: 80 });
  await transport.start({ cwd: process.cwd() });
  const response = await transport.send({ command: 'prompt', arguments: { message: 'bad' } });
  assert.equal(response.success, true);
  const event = await nextEvent(transport, 'worker.diagnostic');
  assert.match(event.message, /late rejection/);
  await transport.stop({ graceMs: 1000 });
});

test('StdioPiTransport still rejects non-prompt commands that time out', async () => {
  const transport = new StdioPiTransport({ executablePath: slowFixture(), commandTimeoutMs: 80 });
  await transport.start({ cwd: process.cwd() });
  await assert.rejects(transport.send({ command: 'get_state' }), /timed out/);
  assert.equal((transport as any).pendingCommands.size, 0);
  await transport.stop({ graceMs: 1000 });
});

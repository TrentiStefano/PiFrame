import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fakePiBin = path.resolve(__dirname, '../../dist/index.js');

describe('fake-pi simulator', () => {
  it('reports correct version 0.85.1', async () => {
    const p = spawn(process.execPath, [fakePiBin, '--version']);
    let out = '';
    p.stdout.on('data', d => out += d.toString());
    const code = await new Promise(r => p.on('close', r));
    assert.strictEqual(code, 0);
    assert.strictEqual(out.trim(), '0.85.1');
  });

  it('replays a fixture byte-for-byte identically', async () => {
    const fixturePath = path.resolve(__dirname, '../../../../packages/pcp-spec/fixtures/pi/text-only.jsonl');
    const originalContent = fs.readFileSync(fixturePath, 'utf8');

    const p = spawn(process.execPath, [fakePiBin, '--replay', fixturePath]);
    let out = '';
    p.stdout.on('data', d => out += d.toString());
    const code = await new Promise(r => p.on('close', r));
    assert.strictEqual(code, 0);
    assert.strictEqual(out, originalContent);
  });

  it('handles get_state and prompt commands in RPC mode', async () => {
    const p = spawn(process.execPath, [fakePiBin, '--mode', 'rpc', '--no-session'], {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    let buffer = '';
    const received: any[] = [];

    const waitForSettled = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for agent_settled')), 3000);
      p.stdout.on('data', d => {
        buffer += d.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';
        for (const line of lines) {
          if (!line.trim()) continue;
          const msg = JSON.parse(line);
          received.push(msg);
          if (msg.type === 'agent_settled') {
            clearTimeout(timeout);
            resolve();
          }
        }
      });
    });

    p.stdin.write(JSON.stringify({ type: 'get_state', id: 'test_state' }) + '\n');
    p.stdin.write(JSON.stringify({ type: 'prompt', id: 'test_prompt', message: 'Hello' }) + '\n');

    await waitForSettled;
    p.kill();

    // Check that we received response to get_state and prompt
    const stateResp = received.find(m => m.command === 'get_state');
    assert.ok(stateResp, 'Expected get_state response');
    assert.strictEqual(stateResp.id, 'test_state');
    assert.strictEqual(stateResp.success, true);

    const promptResp = received.find(m => m.command === 'prompt');
    assert.ok(promptResp, 'Expected prompt response');
    assert.strictEqual(promptResp.id, 'test_prompt');

    // Check that streaming events were emitted
    const startEvent = received.find(m => m.type === 'agent_start');
    assert.ok(startEvent, 'Expected agent_start event');
    const settledEvent = received.find(m => m.type === 'agent_settled');
    assert.ok(settledEvent, 'Expected agent_settled event');
  });
});

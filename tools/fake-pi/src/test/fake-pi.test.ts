import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fakePiBin = path.resolve(__dirname, '../../dist/index.js');
const fakeNpmBin = path.resolve(__dirname, '../../dist/fake-npm.js');

function tempDir(): string {
  return fs.mkdtempSync(path.join(process.env.TEMP || process.env.TMP || process.cwd(), 'fake-pi-test-'));
}

function observeJsonLines(child: ReturnType<typeof spawn>) {
  if (!child.stdout) throw new Error('Child process stdout is unavailable');
  let buffer = '';
  const messages: any[] = [];
  const waiters: Array<{ predicate: (message: any) => boolean; resolve: (message: any) => void }> = [];
  child.stdout.on('data', (data) => {
    buffer += data.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
      if (!line.trim()) continue;
      const message = JSON.parse(line);
      messages.push(message);
      for (let i = waiters.length - 1; i >= 0; i--) {
        if (waiters[i].predicate(message)) waiters.splice(i, 1)[0].resolve(message);
      }
    }
  });
  return {
    messages,
    waitFor(predicate: (message: any) => boolean, timeoutMs = 5000): Promise<any> {
      const existing = messages.find(predicate);
      if (existing) return Promise.resolve(existing);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Timed out waiting for fake-pi RPC message')), timeoutMs);
        waiters.push({
          predicate,
          resolve: (message) => { clearTimeout(timer); resolve(message); }
        });
      });
    }
  };
}

function closed(child: ReturnType<typeof spawn>): Promise<number | null> {
  return new Promise((resolve) => child.on('close', resolve));
}

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

  it('rejects legacy nested command envelopes instead of masking transport bugs', async () => {
    const p = spawn(process.execPath, [fakePiBin, '--mode', 'rpc', '--no-session'], {
      stdio: ['pipe', 'pipe', 'pipe']
    });
    let output = '';
    p.stdout.on('data', d => output += d.toString());
    p.stdin.write(JSON.stringify({ command: 'get_state', arguments: {}, id: 'legacy' }) + '\n');
    p.stdin.end();
    const code = await new Promise<number | null>(resolve => p.on('close', resolve));
    assert.strictEqual(code, 0);
    const response = JSON.parse(output.trim());
    assert.strictEqual(response.type, 'response');
    assert.strictEqual(response.success, false);
    assert.match(response.error, /canonical flat RPC command/);
  });

  it('accepts canonical bash command field and rejects unknown types', async () => {
    const p = spawn(process.execPath, [fakePiBin, '--mode', 'rpc', '--no-session']);
    let output = '';
    p.stdout.on('data', d => output += d.toString());
    p.stdin.write(JSON.stringify({ type: 'bash', command: 'echo test', id: 'bash' }) + '\n');
    p.stdin.write(JSON.stringify({ type: 'does-not-exist', id: 'unknown' }) + '\n');
    p.stdin.end();
    await new Promise(resolve => p.on('close', resolve));
    const responses = output.trim().split('\n').map(line => JSON.parse(line));
    assert.strictEqual(responses[0].success, true);
    assert.strictEqual(responses[0].data.output, 'Fake command: echo test');
    assert.strictEqual(responses[1].success, false);
  });

  it('re-reads the control file for every prompt', async () => {
    const cwd = tempDir();
    const controlFile = path.join(cwd, 'scenario.txt');
    fs.writeFileSync(controlFile, 'hello-world');
    const p = spawn(process.execPath, [fakePiBin, '--mode', 'rpc', '--no-session'], {
      cwd,
      env: { ...process.env, FAKE_PI_CONTROL_FILE: controlFile },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    const observed = observeJsonLines(p);
    p.stdin.write(JSON.stringify({ type: 'prompt', id: 'first', message: 'First prompt' }) + '\n');
    await observed.waitFor((message) => message.type === 'agent_settled');
    fs.writeFileSync(controlFile, 'provider-error');
    p.stdin.write(JSON.stringify({ type: 'prompt', id: 'second', message: 'Second prompt' }) + '\n');
    await observed.waitFor((message) => message.type === 'agent_settled' &&
      observed.messages.filter((entry) => entry.type === 'agent_settled').length === 2);
    p.stdin.end();
    assert.ok(observed.messages.some((message) => message.type === 'message_update' && message.assistantMessageEvent?.delta === 'Hello from fake-pi!'));
    assert.ok(observed.messages.some((message) => message.type === 'message_end' && message.message?.stopReason === 'error'));
    // Scenarios echo the prompt the user actually sent, like real Pi.
    const echoed = observed.messages.find((message) => message.type === 'message_end' &&
      message.message?.role === 'user' && message.message?.content === 'Second prompt');
    assert.ok(echoed);
    assert.ok(typeof echoed.message.timestamp === 'number' && Date.now() - echoed.message.timestamp < 60_000);
    assert.strictEqual(await closed(p), 0);
    fs.rmSync(cwd, { recursive: true, force: true });
  });

  it('serves static scenario overrides for get_tree', async () => {
    const cwd = tempDir();
    const p = spawn(process.execPath, [fakePiBin, '--mode', 'rpc', '--no-session'], {
      cwd,
      env: { ...process.env, FAKE_PI_SCENARIO: 'session-tree' },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    const observed = observeJsonLines(p);
    p.stdin.write(JSON.stringify({ type: 'get_tree', id: 'tree' }) + '\n');
    const response = await observed.waitFor((message) => message.command === 'get_tree');
    p.stdin.end();
    assert.strictEqual(response.data.tree.length, 3);
    assert.strictEqual(response.data.leafId, 'main_answer');
    assert.strictEqual(response.data.tree[2].isLeaf, true);
    assert.strictEqual(await closed(p), 0);
    fs.rmSync(cwd, { recursive: true, force: true });
  });

  it('refuses scenario file writes without the marker and allows them with it', async () => {
    const runEditScenario = async (marked: boolean) => {
      const cwd = tempDir();
      if (marked) fs.writeFileSync(path.join(cwd, '.fake-pi-writable'), '');
      const p = spawn(process.execPath, [fakePiBin, '--mode', 'rpc', '--no-session'], {
        cwd,
        env: { ...process.env, FAKE_PI_SCENARIO: 'edit-files' },
        stdio: ['pipe', 'pipe', 'pipe']
      });
      const observed = observeJsonLines(p);
      let stderr = '';
      p.stderr.on('data', (data) => stderr += data.toString());
      p.stdin.write(JSON.stringify({ type: 'prompt', id: 'edit', message: 'Edit the files' }) + '\n');
      await observed.waitFor((message) => message.type === 'agent_settled');
      p.stdin.end();
      assert.strictEqual(await closed(p), 0);
      const featurePath = path.join(cwd, 'src', 'feature.dart');
      if (marked) assert.strictEqual(fs.readFileSync(featurePath, 'utf8'), 'class Feature {}\n');
      else {
        assert.strictEqual(fs.existsSync(featurePath), false);
        assert.match(stderr, /\.fake-pi-writable marker is missing/);
      }
      fs.rmSync(cwd, { recursive: true, force: true });
    };
    await runEditScenario(false);
    await runEditScenario(true);
  });

  it('prints parseable package list output and creates package manifests and agents', async () => {
    const agentDir = tempDir();
    const p = spawn(process.execPath, [fakePiBin, 'list'], {
      env: { ...process.env, PI_CODING_AGENT_DIR: agentDir },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let output = '';
    p.stdout.on('data', (data) => output += data.toString());
    assert.strictEqual(await closed(p), 0);
    const parsed: Array<{ source: string; installPath?: string }> = [];
    let scope: 'user' | 'project' = 'user';
    let pending: { source: string; installPath?: string } | undefined;
    const flush = () => {
      if (pending && scope === 'user') parsed.push(pending);
      pending = undefined;
    };
    for (const line of output.split(/\r?\n/)) {
      const heading = line.trim();
      if (heading === 'User packages:') { flush(); scope = 'user'; continue; }
      if (heading === 'Project packages:') { flush(); scope = 'project'; continue; }
      if (/^  \S/.test(line) && !/^    /.test(line)) {
        flush();
        pending = { source: line.trim() };
      } else if (pending && /^    \S/.test(line)) {
        pending.installPath = line.trim();
        flush();
      }
    }
    flush();
    const subagents = parsed.find((item) => item.source === 'npm:pi-subagents');
    assert.ok(subagents?.installPath);
    const manifest = JSON.parse(fs.readFileSync(path.join(subagents.installPath!, 'package.json'), 'utf8'));
    assert.strictEqual(manifest.name, 'pi-subagents');
    assert.strictEqual(manifest.version, '0.9.0');
    assert.ok(fs.existsSync(path.join(subagents.installPath!, 'agents', 'reviewer.md')));
    assert.ok(output.startsWith('User packages:\n  npm:pi-subagents\n    '));
    assert.ok(output.includes('\nProject packages:\n'));
    fs.rmSync(agentDir, { recursive: true, force: true });
  });

  it('fake npm view prints the configured latest package version as JSON', async () => {
    const agentDir = tempDir();
    const seed = spawn(process.execPath, [fakePiBin, 'list'], {
      env: { ...process.env, PI_CODING_AGENT_DIR: agentDir },
      stdio: ['ignore', 'ignore', 'ignore']
    });
    assert.strictEqual(await closed(seed), 0);
    const p = spawn(process.execPath, [fakeNpmBin, 'view', 'pi-subagents@latest', 'version', '--json'], {
      env: { ...process.env, PI_CODING_AGENT_DIR: agentDir },
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let output = '';
    p.stdout.on('data', (data) => output += data.toString());
    assert.strictEqual(await closed(p), 0);
    assert.strictEqual(JSON.parse(output.trim()), '0.10.0');
    fs.rmSync(agentDir, { recursive: true, force: true });
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

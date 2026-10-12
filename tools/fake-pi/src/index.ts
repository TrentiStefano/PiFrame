#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { StringDecoder } from 'node:string_decoder';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Framing: LF-only strict JSONL
function send(obj: any): void {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function sendRaw(str: string): void {
  process.stdout.write(str + '\n');
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--version') || args.includes('-v')) {
    console.log('0.85.1');
    process.exit(0);
  }

  // Check for replay mode
  const replayIdx = args.indexOf('--replay');
  if (replayIdx !== -1 && args[replayIdx + 1]) {
    const replayPath = path.resolve(process.cwd(), args[replayIdx + 1]);
    if (!fs.existsSync(replayPath)) {
      console.error(`Replay file not found: ${replayPath}`);
      process.exit(1);
    }
    const lines = fs.readFileSync(replayPath, 'utf8').split('\n').filter(l => l.trim().length > 0);
    for (const line of lines) {
      sendRaw(line);
    }
    process.exit(0);
  }

  // Check for scenario
  let scenarioName = process.env.FAKE_PI_SCENARIO || 'hello-world';
  const scenarioIdx = args.indexOf('--scenario');
  if (scenarioIdx !== -1 && args[scenarioIdx + 1]) {
    scenarioName = args[scenarioIdx + 1];
  }

  const scenarioPath = path.resolve(__dirname, `../scenarios/${scenarioName}.json`);
  let scenarioConfig: any = {};
  if (fs.existsSync(scenarioPath)) {
    try {
      scenarioConfig = JSON.parse(fs.readFileSync(scenarioPath, 'utf8'));
    } catch (e) {
      console.error(`Failed to parse scenario: ${scenarioPath}`);
    }
  }

  let isStreaming = false;
  let abortRequested = false;
  const queue = { steering: [] as string[], followUp: [] as string[] };

  // LF-only line reader (no readline)
  const decoder = new StringDecoder('utf8');
  let inputBuffer = '';

  const processLine = async (line: string) => {
    if (!line.trim()) return;
    let cmd: any;
    try {
      cmd = JSON.parse(line.trim());
    } catch (err: any) {
      send({ id: undefined, type: 'response', command: 'parse', success: false, error: 'Failed to parse JSON' });
      return;
    }

    const id = cmd.id;
    const type = cmd.type;
    if (typeof type !== 'string' || 'arguments' in cmd) {
      send({ id, type: 'response', command: 'parse', success: false, error: 'Expected canonical flat RPC command with type and top-level arguments' });
      return;
    }

    if (type === 'extension_ui_response') {
      return;
    }

    if (type === 'get_state') {
      send({
        id,
        type: 'response',
        command: 'get_state',
        success: true,
        data: {
          model: { id: 'fake-model', name: 'Fake Pi Model', provider: 'fake', reasoning: true, contextWindow: 128000 },
          thinkingLevel: 'low',
          isStreaming,
          isCompacting: false,
          steeringMode: 'one-at-a-time',
          followUpMode: 'one-at-a-time',
          sessionId: 'fake-session-001',
          autoCompactionEnabled: true,
          messageCount: 0,
          pendingMessageCount: 0
        }
      });
      return;
    }

    if (type === 'get_available_thinking_levels') {
      send({
        id,
        type: 'response',
        command: 'get_available_thinking_levels',
        success: true,
        data: { levels: ['off', 'low', 'medium', 'high'] }
      });
      return;
    }

    if (type === 'get_available_models') {
      send({
        id,
        type: 'response',
        command: 'get_available_models',
        success: true,
        data: {
          models: [
            { id: 'fake-model', name: 'Fake Pi Model', provider: 'fake', reasoning: true, contextWindow: 128000 }
          ]
        }
      });
      return;
    }

    if (type === 'get_commands') {
      send({
        id,
        type: 'response',
        command: 'get_commands',
        success: true,
        data: {
          commands: [
            { name: 'help', description: 'Show help', source: 'prompt', sourceInfo: { name: 'help' } },
            { name: 'review', description: 'Review changes', source: 'skill', sourceInfo: { name: 'review' } }
          ]
        }
      });
      return;
    }

    if (type === 'get_entries') {
      send({
        id,
        type: 'response',
        command: 'get_entries',
        success: true,
        data: { entries: [], leafId: null }
      });
      return;
    }

    if (type === 'get_tree') {
      send({
        id,
        type: 'response',
        command: 'get_tree',
        success: true,
        data: { tree: [], leafId: null }
      });
      return;
    }

    if (type === 'get_session_stats') {
      send({
        id,
        type: 'response',
        command: 'get_session_stats',
        success: true,
        data: { tokens: { input: 100, output: 50, total: 150 }, cost: 0.001, contextUsage: { percent: 1.2 } }
      });
      return;
    }

    if (type === 'clear_queue') {
      const removed = { steering: [...queue.steering], followUp: [...queue.followUp] };
      queue.steering = [];
      queue.followUp = [];
      send({
        id,
        type: 'response',
        command: 'clear_queue',
        success: true,
        data: removed
      });
      send({ type: 'queue_update', steering: [], followUp: [] });
      return;
    }

    if (type === 'steer') {
      queue.steering.push(cmd.message || '');
      send({ id, type: 'response', command: 'steer', success: true });
      send({ type: 'queue_update', steering: queue.steering, followUp: queue.followUp });
      return;
    }

    if (type === 'follow_up') {
      queue.followUp.push(cmd.message || '');
      send({ id, type: 'response', command: 'follow_up', success: true });
      send({ type: 'queue_update', steering: queue.steering, followUp: queue.followUp });
      return;
    }

    if (type === 'abort') {
      abortRequested = true;
      isStreaming = false;
      send({ id, type: 'response', command: 'abort', success: true });
      send({ type: 'agent_end', messages: [], willRetry: false });
      send({ type: 'agent_settled' });
      return;
    }

    if (type === 'compact') {
      send({
        id,
        type: 'response',
        command: 'compact',
        success: true,
        data: { tokensBefore: 10000, tokensAfter: 2000, cost: 0.02 }
      });
      send({ type: 'compaction_start', reason: 'manual' });
      send({ type: 'compaction_end', result: { tokensBefore: 10000, tokensAfter: 2000, cost: 0.02 }, aborted: false, willRetry: false });
      return;
    }

    if (type === 'prompt') {
      if (isStreaming && !cmd.streamingBehavior) {
        send({ id, type: 'response', command: 'prompt', success: false, error: 'Streaming active. Use streamingBehavior: steer or followUp.' });
        return;
      }

      send({ id, type: 'response', command: 'prompt', success: true });
      isStreaming = true;
      abortRequested = false;

      const events = scenarioConfig.events || [
        { delayMs: 10, event: { type: 'agent_start' } },
        { delayMs: 10, event: { type: 'turn_start' } },
        { event: { type: 'message_start', message: { role: 'user', content: cmd.message, timestamp: Date.now() } } },
        { event: { type: 'message_end', message: { role: 'user', content: cmd.message, timestamp: Date.now() } } },
        { delayMs: 10, event: { type: 'message_start', message: { role: 'assistant', content: [] } } },
        { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 5, total: 105 }, assistantMessageEvent: { type: 'text_start', contentIndex: 0 } } },
        { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 15, total: 115 }, assistantMessageEvent: { type: 'text_delta', contentIndex: 0, delta: 'Hello from fake-pi!' } } },
        { delayMs: 10, event: { type: 'message_update', usage: { input: 100, output: 20, total: 120 }, assistantMessageEvent: { type: 'text_end', contentIndex: 0, content: 'Hello from fake-pi!' } } },
        { delayMs: 10, event: { type: 'message_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello from fake-pi!' }] } } },
        { delayMs: 10, event: { type: 'turn_end', message: { role: 'assistant', content: [{ type: 'text', text: 'Hello from fake-pi!' }] }, toolResults: [] } },
        { delayMs: 10, event: { type: 'agent_end', messages: [{ role: 'assistant', content: [{ type: 'text', text: 'Hello from fake-pi!' }] }], willRetry: false } },
        { delayMs: 10, event: { type: 'agent_settled' } }
      ];

      for (const step of events) {
        if (abortRequested) break;
        if (step.delayMs) {
          await new Promise(r => setTimeout(r, step.delayMs));
        }
        if (abortRequested) break;

        if (step.crash) {
          process.exit(step.exitCode || 1);
        }
        if (step.malformed) {
          sendRaw('{ malformed json line ...');
          continue;
        }
        if (step.event) {
          send(step.event);
        }
      }

      isStreaming = false;
      return;
    }

    if (type === 'bash') {
      send({ id, type: 'response', command: type, success: true,
        data: { output: `Fake command: ${cmd.command}`, exitCode: 0, cancelled: false, truncated: false } });
      return;
    }
    const supportedSetters = ['set_model', 'set_thinking_level', 'set_session_name',
      'set_auto_compaction', 'set_auto_retry', 'set_steering_mode', 'set_follow_up_mode'];
    send({ id, type: 'response', command: type, success: supportedSetters.includes(type), data: {},
      error: supportedSetters.includes(type) ? undefined : `Unknown command type: ${type}` });
  };

  process.stdin.on('data', chunk => {
    inputBuffer += typeof chunk === 'string' ? chunk : decoder.write(chunk);
    while (true) {
      const idx = inputBuffer.indexOf('\n');
      if (idx === -1) break;
      const line = inputBuffer.slice(0, idx).replace(/\r$/, '');
      inputBuffer = inputBuffer.slice(idx + 1);
      void processLine(line);
    }
  });

  process.stdin.on('end', () => {
    process.exit(0);
  });
}

main().catch(err => {
  console.error('fake-pi error:', err);
  process.exit(1);
});

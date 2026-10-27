import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { discoverPi } from '../../apps/agentd/dist/pi/discovery.js';
import { StdioPiTransport } from '../../apps/agentd/dist/pi/StdioPiTransport.js';
import { ensureContextLimitExtension, applyContextPolicy } from '../../apps/agentd/dist/pi/contextLimitExtension.js';

// Real Pi, isolated settings, loopback model. Never call a paid provider or touch user auth/settings.
const installation = await discoverPi(process.env.PI_FRAME_REAL_PI_PATH);
assert.ok(installation.found && installation.supported, installation.hint);
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-context-smoke-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = path.join(directory, 'frame');
const agent = path.join(directory, 'agent');
fs.mkdirSync(agent);
let requests = 0;
let summaryRequests = 0;
let sawCompaction = false;
let finishCompaction;
const compacted = new Promise(resolve => { finishCompaction = resolve; });
const server = http.createServer((req, res) => {
  if (!req.url.endsWith('/chat/completions')) { res.writeHead(404).end(); return; }
  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    const payload = JSON.parse(body);
    const isSummary = JSON.stringify(payload.messages).includes('summar') && sawCompaction;
    if (isSummary) summaryRequests++; else requests++;
    const inputTokens = isSummary ? 500 : [60000, 120000, 195000][Math.min(requests - 1, 2)];
    const text = isSummary ? 'Summary: preserve the three user messages and continue the task.' : 'Answer. '.repeat(1500);
    const usage = { prompt_tokens: inputTokens, completion_tokens: isSummary ? 20 : 1500, total_tokens: inputTokens + (isSummary ? 20 : 1500) };
    if (payload.stream === false) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ id: 'context-smoke', object: 'chat.completion', choices: [{ index: 0, message: { role: 'assistant', content: text }, finish_reason: 'stop' }], usage }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    const chunk = (delta, finish_reason = null, extra = {}) => ({ id: 'context-smoke', object: 'chat.completion.chunk', model: 'smoke', choices: [{ index: 0, delta, finish_reason }], ...extra });
    for (const frame of [chunk({ role: 'assistant' }), chunk({ content: text }), chunk({}, 'stop', { usage })]) res.write(`data: ${JSON.stringify(frame)}\n\n`);
    res.end('data: [DONE]\n\n');
  });
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
fs.writeFileSync(path.join(agent, 'models.json'), JSON.stringify({ providers: { 'frame-context-test': {
  baseUrl: `http://127.0.0.1:${server.address().port}/v1`, api: 'openai-completions', apiKey: 'loopback-only',
  models: [{ id: 'smoke', name: 'Context smoke', reasoning: false, input: ['text'], contextWindow: 1000000, maxTokens: 16000,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
} } }));
fs.writeFileSync(path.join(agent, 'settings.json'), JSON.stringify({ defaultProvider: 'frame-context-test', defaultModel: 'smoke', packages: [], compaction: { enabled: true } }));
const transport = new StdioPiTransport({ executablePath: installation.path });
const events = [];
let settleTurn;
let eventPump;
try {
  await transport.start({ cwd: directory, env: { PI_CODING_AGENT_DIR: agent, PI_OFFLINE: '1' }, args: [
    '--mode', 'rpc', '--offline', '--no-extensions', '--extension', ensureContextLimitExtension(),
    '--no-mcp', '--no-skills', '--no-prompt-templates', '--no-context-files', '--no-tools', '--no-session',
  ] });
  eventPump = (async () => {
    for await (const event of transport.events()) {
      events.push(event);
      if (event.type === 'agent_settled') { settleTurn?.(); settleTurn = undefined; }
      if (event.type === 'compaction_start') sawCompaction = true;
      if (event.type === 'compaction_end') finishCompaction(event);
    }
  })();
  const initial = (await transport.send({ command: 'get_state' })).data;
  assert.equal(initial.model.piframeContextPolicy?.percent, 2.5, 'default policy must be active on fresh workers');
  const model = await applyContextPolicy(transport, { contextWindowOverride: 200000, compactionReservePercent: 2.5 });
  assert.equal(model.contextWindow, 1000000);
  let state = (await transport.send({ command: 'get_state' })).data;
  assert.equal(state.model.contextWindow - 16384, 194999);
  assert.equal(requests, 0, 'configuration must not submit a model request');
  for (let turn = 0; turn < 3; turn++) {
    const settled = new Promise(resolve => { settleTurn = resolve; });
    await transport.send({ command: 'prompt', arguments: { message: `Turn ${turn}: ${'context material '.repeat(3000)}` } });
    const timeout = setTimeout(() => settleTurn?.(), 20000);
    try { await settled; } finally { clearTimeout(timeout); }
    if (turn === 0) {
      const live = (await transport.send({ command: 'get_state' })).data;
      assert.ok(live.model.piframeContextUsage.tokens >= 60000, 'context statistics must come from live Pi context usage');
    }
  }
  const deadline = setTimeout(() => finishCompaction({ errorMessage: 'Compaction timeout' }), 20000);
  let result;
  try { result = await compacted; } finally { clearTimeout(deadline); }
  assert.equal(result.errorMessage, undefined, JSON.stringify(result));
  assert.ok(summaryRequests > 0, 'real Pi must compact at the selected 200k tier, not 1M');
  await applyContextPolicy(transport, { contextWindowOverride: 1000000, compactionReservePercent: 5 });
  state = (await transport.send({ command: 'get_state' })).data;
  assert.equal(state.model.contextWindow - 16384, 949999);
  console.log(`Pi ${installation.version}: 200k tier -> 195k compaction, 1M/5% -> 950k, physical maximum preserved, no paid calls PASS.`);
} finally {
  await transport.stop({ graceMs: 1000 });
  await eventPump;
  await new Promise(resolve => server.close(resolve));
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME; else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(directory, { recursive: true, force: true });
}

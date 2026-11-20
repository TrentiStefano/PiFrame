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

  // If env configured log file, record argv
  if (process.env.FAKE_PI_LOG_FILE) {
    try {
      fs.appendFileSync(process.env.FAKE_PI_LOG_FILE, JSON.stringify({ argv: args, pid: process.pid, ts: Date.now() }) + '\n');
    } catch {}
  }

  // Parse key flags for RPC reflection
  const toolsIdx = args.indexOf('--tools');
  const toolList = toolsIdx !== -1 && args[toolsIdx + 1]
    ? args[toolsIdx + 1].split(',').map((s) => s.trim()).filter(Boolean)
    : undefined;
  const modelIdx = args.indexOf('--model');
  const passedModelPattern = modelIdx !== -1 && args[modelIdx + 1] ? args[modelIdx + 1] : undefined;
  const thinkingIdx = args.indexOf('--thinking');
  const passedThinking = thinkingIdx !== -1 && args[thinkingIdx + 1] ? args[thinkingIdx + 1] : undefined;

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

  const scenarioIdx = args.indexOf('--scenario');
  const cliScenario = scenarioIdx !== -1 && args[scenarioIdx + 1] ? args[scenarioIdx + 1] : undefined;
  const selectedScenarioName = (): string => {
    const controlFile = process.env.FAKE_PI_CONTROL_FILE;
    if (controlFile && fs.existsSync(controlFile)) {
      try {
        return fs.readFileSync(controlFile, 'utf8').trim();
      } catch (error) {
        console.error(`Unable to read FAKE_PI_CONTROL_FILE: ${String(error)}`);
      }
    }
    return process.env.FAKE_PI_SCENARIO || cliScenario || 'hello-world';
  };
  const readScenario = (): any => {
    let name = selectedScenarioName();
    const scenariosDir = path.resolve(__dirname, '../scenarios');
    let scenarioPath = path.resolve(scenariosDir, `${name}.json`);
    const scenarioRelative = path.relative(scenariosDir, scenarioPath);
    if (!name || name.includes('/') || name.includes('\\') || scenarioRelative.startsWith('..') || path.isAbsolute(scenarioRelative) || !fs.existsSync(scenarioPath)) {
      console.error(`Unknown fake-pi scenario '${name}', falling back to hello-world.`);
      name = 'hello-world';
      scenarioPath = path.resolve(__dirname, '../scenarios/hello-world.json');
    }
    try {
      return JSON.parse(fs.readFileSync(scenarioPath, 'utf8'));
    } catch (error) {
      console.error(`Failed to parse scenario: ${scenarioPath}: ${String(error)}`);
      return {};
    }
  };

  const writeScenarioFile = (operation: 'writeFile' | 'appendFile', spec: any): void => {
    try {
      const cwd = path.resolve(process.cwd());
      if (!fs.existsSync(path.join(cwd, '.fake-pi-writable'))) {
        console.error(`fake-pi refused ${operation}: .fake-pi-writable marker is missing in ${cwd}`);
        return;
      }
      if (!spec || typeof spec.path !== 'string' || path.isAbsolute(spec.path)) {
        console.error(`fake-pi refused ${operation}: path must be relative`);
        return;
      }
      const target = path.resolve(cwd, spec.path);
      const relative = path.relative(cwd, target);
      if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
        console.error(`fake-pi refused ${operation}: path escapes session cwd`);
        return;
      }
      const segments = relative.split(path.sep);
      let parent = cwd;
      for (const segment of segments.slice(0, -1)) {
        parent = path.join(parent, segment);
        try {
          const parentStat = fs.lstatSync(parent);
          if (parentStat.isSymbolicLink() || !parentStat.isDirectory()) {
            console.error(`fake-pi refused ${operation}: parent path is not a real directory`);
            return;
          }
        } catch (error: any) {
          if (error?.code !== 'ENOENT') throw error;
          fs.mkdirSync(parent);
        }
      }
      const realCwd = fs.realpathSync(cwd);
      const realParent = fs.realpathSync(parent);
      const realRelative = path.relative(realCwd, realParent);
      if (realRelative === '..' || realRelative.startsWith(`..${path.sep}`) || path.isAbsolute(realRelative)) {
        console.error(`fake-pi refused ${operation}: resolved path escapes session cwd`);
        return;
      }
      try {
        const targetStat = fs.lstatSync(target);
        if (targetStat.isSymbolicLink() || (targetStat.isFile() && targetStat.nlink > 1)) {
          console.error(`fake-pi refused ${operation}: refusing symbolic links and hard-linked files`);
          return;
        }
        const realTarget = fs.realpathSync(target);
        const targetRelative = path.relative(realCwd, realTarget);
        if (targetRelative === '..' || targetRelative.startsWith(`..${path.sep}`) || path.isAbsolute(targetRelative)) {
          console.error(`fake-pi refused ${operation}: resolved path escapes session cwd`);
          return;
        }
      } catch (error: any) {
        if (error?.code !== 'ENOENT') throw error;
      }
      const content = typeof spec.content === 'string' ? spec.content : '';
      if (operation === 'writeFile') fs.writeFileSync(target, content, 'utf8');
      else fs.appendFileSync(target, content, 'utf8');
    } catch (error) {
      console.error(`fake-pi refused ${operation}: ${String(error)}`);
    }
  };

  const agentDir = path.resolve(process.env.PI_CODING_AGENT_DIR || path.join(process.env.HOME || process.env.USERPROFILE || process.cwd(), '.pi', 'agent'));
  const packagesFile = path.join(agentDir, 'fake-packages.json');
  const defaultPackages = [
    { source: 'npm:pi-subagents', version: '0.9.0', latest: '0.10.0' },
    { source: 'npm:@juicesharp/rpiv-ask-user-question', version: '1.2.0', latest: '1.2.0' },
    { source: 'npm:pi-caveman@1.0.0', version: '1.0.0', latest: '1.0.0' },
    { source: 'git:github.com/example/pi-theme-pack', version: null, latest: null }
  ];
  const packageName = (source: string): string => {
    if (!source.startsWith('npm:')) return source;
    const spec = source.slice(4);
    const slash = spec.lastIndexOf('/');
    const at = spec.lastIndexOf('@');
    return at > slash ? spec.slice(0, at) : spec;
  };
  const packageVersion = (source: string, fallback = '1.0.0'): string => {
    const spec = source.slice(4);
    const slash = spec.lastIndexOf('/');
    const at = spec.lastIndexOf('@');
    return at > slash ? spec.slice(at + 1) : fallback;
  };
  const loadPackages = (): any[] => {
    fs.mkdirSync(agentDir, { recursive: true });
    if (!fs.existsSync(packagesFile)) fs.writeFileSync(packagesFile, JSON.stringify(defaultPackages, null, 2));
    try {
      const loaded = JSON.parse(fs.readFileSync(packagesFile, 'utf8'));
      return Array.isArray(loaded) ? loaded : [...defaultPackages];
    } catch { return [...defaultPackages]; }
  };
  const savePackages = (packages: any[]): void => {
    fs.mkdirSync(agentDir, { recursive: true });
    fs.writeFileSync(packagesFile, JSON.stringify(packages, null, 2));
    for (const item of packages) {
      if (!String(item.source).startsWith('npm:')) continue;
      const name = packageName(item.source);
      const installDir = path.join(agentDir, 'npm', 'node_modules', name);
      fs.mkdirSync(installDir, { recursive: true });
      fs.writeFileSync(path.join(installDir, 'package.json'), JSON.stringify({ name, version: item.version || packageVersion(item.source) }, null, 2));
      if (name === 'pi-subagents') {
        const agentsDir = path.join(installDir, 'agents');
        fs.mkdirSync(agentsDir, { recursive: true });
        fs.writeFileSync(path.join(agentsDir, 'reviewer.md'), '---\nname: reviewer\ndescription: Review changes offline\n---\nReview the requested changes carefully.\n');
      }
    }
  };
  const runCli = (): boolean => {
    const command = args[0];
    if (args.includes('--list-models')) {
      console.log('Provider  Model          Context  Reasoning');
      console.log('fake      fake-model     128000   yes');
      console.log('fake      fake-fast      64000    no');
      console.log('openai    gpt-4o-mini    128000   yes');
      return true;
    }
    if (command === 'list') {
      const packages = loadPackages();
      savePackages(packages);
      console.log('User packages:');
      for (const item of packages) {
        console.log(`  ${item.source}`);
        if (String(item.source).startsWith('npm:')) console.log(`    ${path.join(agentDir, 'npm', 'node_modules', packageName(item.source))}`);
      }
      console.log('Project packages:');
      return true;
    }
    if (command === 'install' && args[1]) {
      const source = args[1];
      const packages = loadPackages().filter((item) => item.source !== source && item.source !== `npm:${packageName(source)}`);
      const version = source.startsWith('npm:') ? packageVersion(source, '1.0.0') : '1.0.0';
      packages.push({ source, version, latest: version });
      savePackages(packages);
      console.log(`Installing ${source}...`);
      console.log(`Installed ${source} (${version}).`);
      return true;
    }
    if (command === 'remove' && args[1]) {
      const source = args[1];
      const packages = loadPackages().filter((item) => item.source !== source);
      savePackages(packages);
      if (source.startsWith('npm:')) {
        const installDir = path.join(agentDir, 'npm', 'node_modules', packageName(source));
        fs.rmSync(installDir, { recursive: true, force: true });
      }
      console.log(`Removed ${source}.`);
      return true;
    }
    if (command === 'update') {
      const packages = loadPackages();
      const target = args[1];
      for (const item of packages) {
        if (!target || target === '--all' || target === '--extensions' || target === '--models' || item.source === target) {
          const pinned = item.source.startsWith('npm:') && item.source !== `npm:${packageName(item.source)}`;
          if (item.latest && !pinned) item.version = item.latest;
          console.log(`Updated ${item.source} to ${item.version || 'latest'}.`);
        }
      }
      savePackages(packages);
      return true;
    }
    if (command === 'mcp' && args[1] === 'list') {
      const servers = [
        { name: 'local-files', enabled: true, state: 'connected', transport: 'stdio node local-files.js', source: path.join(agentDir, 'mcp.json'), scope: 'global', tools: ['read_file', 'list_directory'] },
        { name: 'offline-search', enabled: true, state: 'failed', transport: 'stdio node offline-search.js', source: path.join(agentDir, 'mcp.json'), scope: 'global', tools: [], error: 'Offline simulator: server unavailable' }
      ];
      if (args.includes('--json')) console.log(JSON.stringify({ servers }));
      else {
        console.log('MCP servers:');
        for (const server of servers) console.log(`${server.name}  ${server.state}  ${server.tools.length} tools`);
      }
      return true;
    }
    return false;
  };
  if (runCli()) return;

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
      const modelObj = passedModelPattern
        ? {
            id: passedModelPattern.includes('/') ? passedModelPattern.split('/')[1] : passedModelPattern,
            provider: passedModelPattern.includes('/') ? passedModelPattern.split('/')[0] : 'fake',
            name: passedModelPattern,
            reasoning: true,
            contextWindow: 128000
          }
        : { id: 'fake-model', name: 'Fake Pi Model', provider: 'fake', reasoning: true, contextWindow: 128000 };

      send({
        id,
        type: 'response',
        command: 'get_state',
        success: true,
        data: {
          model: modelObj,
          thinkingLevel: passedThinking || 'low',
          isStreaming,
          isCompacting: false,
          steeringMode: 'one-at-a-time',
          followUpMode: 'one-at-a-time',
          sessionId: 'fake-session-001',
          autoCompactionEnabled: true,
          messageCount: 0,
          pendingMessageCount: 0,
          argv: args,
          tools: toolList || ['read', 'bash', 'edit', 'write']
        }
      });
      return;
    }

    if (type === 'get_messages') {
      send({
        id,
        type: 'response',
        command: 'get_messages',
        success: true,
        data: {
          messages: readScenario().messages || [
            {
              role: 'user',
              content: [{ type: 'text', text: 'Hello, what is this project?' }],
              timestamp: Date.now() - 60000
            },
            {
              role: 'assistant',
              content: [
                { type: 'text', text: 'This is PiFrame, a local GUI for Pi.' },
                {
                  type: 'toolCall',
                  id: 'tc_001',
                  name: 'read',
                  arguments: { path: 'README.md' }
                }
              ],
              timestamp: Date.now() - 30000
            },
            {
              role: 'toolResult',
              toolCallId: 'tc_001',
              toolName: 'read',
              content: [{ type: 'text', text: '# PiFrame\nWorkspace and session manager.' }],
              isError: false,
              timestamp: Date.now() - 25000
            }
          ]
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
          models: readScenario().models || [
            {
              id: 'fake-model',
              name: 'Fake Pi Model',
              provider: 'fake',
              reasoning: true,
              contextWindow: 128000,
              cost: {
                tiers: [{ inputTokensAbove: 64000 }]
              }
            },
            {
              id: 'fake-fast',
              name: 'Fake Fast Model',
              provider: 'fake',
              reasoning: false,
              contextWindow: 64000
            },
            {
              id: 'gpt-4o-mini',
              name: 'GPT-4o mini',
              provider: 'openai',
              reasoning: true,
              contextWindow: 128000
            }
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
          commands: readScenario().commands || [
            { name: 'help', description: 'Show help', source: 'prompt', sourceInfo: { name: 'help' }, argumentHint: '[topic]' },
            { name: 'review', description: 'Review changes', source: 'skill', sourceInfo: { name: 'review' }, argumentHint: '[files]' },
            { name: 'status', description: 'Show detailed extension status', source: 'extension', sourceInfo: { name: 'fake-pi' }, argumentHint: '<verbose|short>' }
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
        data: (() => { const scenario = readScenario(); return { entries: scenario.entries || [], leafId: scenario.leafId ?? null }; })()
      });
      return;
    }

    if (type === 'get_tree') {
      send({
        id,
        type: 'response',
        command: 'get_tree',
        success: true,
        data: (() => { const scenario = readScenario(); return { tree: scenario.tree || [], leafId: scenario.leafId ?? null }; })()
      });
      return;
    }

    if (type === 'get_session_stats') {
      send({
        id,
        type: 'response',
        command: 'get_session_stats',
        success: true,
        data: readScenario().stats || { tokens: { input: 100, output: 50, total: 150 }, cost: 0.001, contextUsage: { tokens: 150, contextWindow: 128000, percent: 0.12 } }
      });
      return;
    }

    if (type === 'fork' || type === 'clone') {
      send({ id, type: 'response', command: type, success: true, data: { cancelled: false } });
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
        data: { tokensBefore: 10000, tokensAfter: 2000, estimatedTokensAfter: 2000, cost: 0.02 }
      });
      send({ type: 'compaction_start', reason: 'manual' });
      send({ type: 'compaction_end', result: { tokensBefore: 10000, tokensAfter: 2000, estimatedTokensAfter: 2000, cost: 0.02 }, aborted: false, willRetry: false });
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

      const scenarioConfig = readScenario();
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
        if (step.writeFile) writeScenarioFile('writeFile', step.writeFile);
        if (step.appendFile) writeScenarioFile('appendFile', step.appendFile);
        if (step.event) {
          // Real Pi echoes the user's own prompt and stamps it with the send time; scenarios mark
          // those slots with {{prompt}} and "{{now}}".
          const prompt = typeof cmd.message === 'string' ? cmd.message : '';
          const raw = JSON.stringify(step.event);
          send(raw.includes('{{')
            ? JSON.parse(raw
              .split('{{prompt}}').join(JSON.stringify(prompt).slice(1, -1))
              .split('"{{now}}"').join(String(Date.now())))
            : step.event);
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

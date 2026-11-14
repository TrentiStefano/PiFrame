#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';

const execFileAsync = promisify(execFile);
const SCRIPT = fileURLToPath(import.meta.url);
const ROOT = path.resolve(path.dirname(SCRIPT), '../..');
const HARNESS_ROOT = path.join(os.homedir(), '.piframe-harness');
const DEFAULT_TIMEOUT = 6 * 60 * 1000;

export function parseSelector(value) {
  const match = String(value).match(/^(.*)#(\d+)$/);
  const raw = match ? match[1] : String(value);
  const index = match ? Number(match[2]) : undefined;
  if (!raw) throw new Error('Selector cannot be empty');
  if (raw.startsWith('key:')) return { type: 'key', value: raw.slice(4), ...(index === undefined ? {} : { index }) };
  if (raw.startsWith('text:')) return { type: 'text', value: raw.slice(5), ...(index === undefined ? {} : { index }) };
  return { type: 'text', value: raw, ...(index === undefined ? {} : { index }) };
}

export function encodeParams(params = {}) {
  return Object.fromEntries(Object.entries(params).map(([key, value]) => [key, typeof value === 'string' ? value : JSON.stringify(value)]));
}

export function isMissingProcessError(error) {
  return error.code === 128 || /not found|no running instance|non trovato/i.test(
    `${error.message || ''} ${error.stdout || ''} ${error.stderr || ''}`,
  );
}

export function assertSafeHome(home, userHome = os.homedir()) {
  const prospectiveRealPath = (value) => {
    const absolute = path.resolve(value);
    let existing = absolute;
    const suffix = [];
    while (!fs.existsSync(existing)) {
      suffix.unshift(path.basename(existing));
      const parent = path.dirname(existing);
      if (parent === existing) break;
      existing = parent;
    }
    return path.resolve(fs.realpathSync(existing), ...suffix);
  };
  const resolved = prospectiveRealPath(home);
  const forbidden = ['.piframe', '.piframe-dev'].map((name) => prospectiveRealPath(path.join(userHome, name)));
  const norm = (value) => process.platform === 'win32' ? value.toLowerCase() : value;
  if (forbidden.some((item) => {
    const target = norm(resolved);
    const protectedHome = norm(item);
    return target === protectedHome || target.startsWith(`${protectedHome}${path.sep}`);
  })) {
    throw new Error(`Refusing unsafe harness home: ${resolved} is inside a real PiFrame home`);
  }
  return resolved;
}

const scenarioDirectory = path.join(ROOT, 'tools', 'fake-pi', 'scenarios');

export function listScenarios() {
  const indexFile = path.join(scenarioDirectory, 'index.json');
  if (fs.existsSync(indexFile)) {
    const index = JSON.parse(fs.readFileSync(indexFile, 'utf8'));
    if (!Array.isArray(index) || index.some((item) => typeof item?.name !== 'string')) {
      throw new Error('Invalid fake-pi scenarios/index.json; expected an array of named scenarios');
    }
    return index;
  }
  if (!fs.existsSync(scenarioDirectory)) return [];
  return fs.readdirSync(scenarioDirectory)
    .filter((name) => name.endsWith('.json') && name !== 'index.json')
    .sort()
    .map((file) => {
      const name = path.basename(file, '.json');
      let details = {};
      try { details = JSON.parse(fs.readFileSync(path.join(scenarioDirectory, file), 'utf8')); } catch { }
      return { name, description: details.description || '', covers: details.covers || [] };
    });
}

export function validateScenarioName(name) {
  if (typeof name !== 'string' || !listScenarios().some((scenario) => scenario.name === name)) {
    throw new Error(`Unknown fake-pi scenario: ${name || '(missing)'}`);
  }
  return name;
}

function runDir(runName) {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(runName)) throw new Error(`Invalid run name: ${runName}`);
  return assertSafeHome(path.join(HARNESS_ROOT, runName));
}

function readState(home) {
  try { return JSON.parse(fs.readFileSync(path.join(home, 'harness.json'), 'utf8')); } catch { return null; }
}

function writeState(home, state) {
  fs.mkdirSync(home, { recursive: true });
  const tmp = path.join(home, `harness.json.tmp.${process.pid}`);
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, path.join(home, 'harness.json'));
}

function daemonPid(home) {
  const file = path.join(home, 'runtime', 'daemon.json');
  try {
    const resolvedHome = fs.realpathSync(home);
    const resolvedFile = fs.realpathSync(file);
    const relative = path.relative(resolvedHome, resolvedFile);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) return undefined;
    const pid = Number(JSON.parse(fs.readFileSync(resolvedFile, 'utf8')).pid);
    return Number.isInteger(pid) && pid > 0 ? pid : undefined;
  } catch { return undefined; }
}

// The sole process-kill path. A PID must belong to this run or be its daemon PID.
async function killOwned(pid, home, { tree = false, daemon = false } = {}) {
  const state = readState(home);
  const owned = Array.isArray(state?.ownedPids) && state.ownedPids.includes(Number(pid));
  const isDaemon = daemon && daemonPid(home) === Number(pid);
  if (!owned && !isDaemon) throw new Error(`Refusing to kill unowned PID ${pid}`);
  if (process.platform === 'win32') {
    const args = ['/PID', String(pid), '/F'];
    if (tree) args.push('/T');
    try { await execFileAsync('taskkill', args, { windowsHide: true }); }
    catch (error) {
      if (!isMissingProcessError(error)) throw error;
    }
  } else {
    try { process.kill(tree ? -Number(pid) : Number(pid), 'SIGTERM'); }
    catch (error) { if (error.code !== 'ESRCH') throw error; }
  }
}

export function parseArgs(argv) {
  const positional = [];
  const options = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith('--')) {
      const [key, inline] = arg.slice(2).split('=', 2);
      if (['no-daemon-build', 'real-pi', 'daemon', 'all', 'seed', 'reset', 'ctrl', 'shift', 'alt', 'meta'].includes(key)) options[key] = true;
      else {
        const value = inline ?? argv[++i];
        if (value === undefined || value.startsWith('--')) throw new Error(`Missing value for --${key}`);
        options[key] = value;
      }
    } else positional.push(arg);
  }
  return { positional, options };
}

async function run(command, args, opts = {}) {
  await execFileAsync(command, args, { cwd: ROOT, windowsHide: true, maxBuffer: 8 * 1024 * 1024, shell: process.platform === 'win32', ...opts });
}

function walkNewest(dir, ignored = new Set(['node_modules', 'dist', 'build', '.git'])) {
  let newest = 0;
  if (!fs.existsSync(dir)) return newest;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && ignored.has(entry.name)) continue;
    const file = path.join(dir, entry.name);
    try {
      if (entry.isDirectory()) newest = Math.max(newest, walkNewest(file, ignored));
      else if (entry.isFile()) newest = Math.max(newest, fs.statSync(file).mtimeMs);
    } catch { }
  }
  return newest;
}

async function ensureBuilds(noDaemonBuild, force = false) {
  const agentdSources = path.join(ROOT, 'apps', 'agentd', 'src');
  const bundle = path.join(ROOT, 'apps', 'agentd', 'dist', 'pi-agentd.cjs');
  if (!noDaemonBuild && (force || !fs.existsSync(bundle) || walkNewest(agentdSources) > fs.statSync(bundle).mtimeMs)) {
    console.log('Building agentd bundle...');
    await run('pnpm', ['run', 'build:agentd']);
  }
  const fakeSources = path.join(ROOT, 'tools', 'fake-pi', 'src');
  const fakeEntrypoint = path.join(ROOT, 'tools', 'fake-pi', 'dist', 'index.js');
  if (!fs.existsSync(fakeEntrypoint) || walkNewest(fakeSources) > fs.statSync(fakeEntrypoint).mtimeMs) {
    console.log('Building fake-pi...');
    await run('pnpm', ['--filter', '@piframe/fake-pi', 'build']);
  }
  if (!fs.existsSync(bundle)) throw new Error(`Missing agentd bundle: ${bundle}; remove --no-daemon-build or build it first`);
  if (!fs.existsSync(fakeEntrypoint)) throw new Error(`Missing fake-pi entrypoint: ${fakeEntrypoint}`);
}

function writeScenarioControlFile(home, scenario) {
  const safeHome = assertSafeHome(home);
  fs.mkdirSync(safeHome, { recursive: true });
  fs.writeFileSync(path.join(safeHome, 'fake-pi-scenario'), `${scenario}\n`, { mode: 0o600 });
}

function writeFakePiShims(home) {
  const safeHome = assertSafeHome(home);
  const fakeEntrypoint = path.join(ROOT, 'tools', 'fake-pi', 'dist', 'index.js');
  const piShim = process.platform === 'win32' ? path.join(safeHome, 'pi.cmd') : path.join(safeHome, 'pi');
  if (process.platform === 'win32') {
    fs.writeFileSync(piShim, `@echo off\r\n"${process.execPath}" "${fakeEntrypoint}" %*\r\n`, { mode: 0o700 });
  } else {
    fs.writeFileSync(piShim, `#!/bin/sh\nexec "${process.execPath}" "${fakeEntrypoint}" "$@"\n`, { mode: 0o700 });
    fs.chmodSync(piShim, 0o700);
  }
  const npmShim = path.join(safeHome, 'node_modules', 'npm', 'bin', 'npm-cli.js');
  const fakeNpm = path.join(ROOT, 'tools', 'fake-pi', 'dist', 'fake-npm.js');
  fs.mkdirSync(path.dirname(npmShim), { recursive: true });
  fs.writeFileSync(npmShim, [
    "const { spawnSync } = require('node:child_process');",
    `const fakeNpm = ${JSON.stringify(fakeNpm)};`,
    'const result = spawnSync(process.execPath, [fakeNpm, ...process.argv.slice(2)], { stdio: \'inherit\' });',
    'if (result.error) { console.error(result.error.message); process.exit(1); }',
    'process.exit(result.status ?? 1);',
    '',
  ].join('\n'), { mode: 0o600 });
  return piShim;
}

async function runGit(repo, args) {
  return execFileAsync('git', args, { cwd: repo, windowsHide: true, maxBuffer: 1024 * 1024 });
}

function appendExclude(repo, value) {
  const exclude = path.join(repo, '.git', 'info', 'exclude');
  let content = '';
  try { content = fs.readFileSync(exclude, 'utf8'); } catch { }
  if (!content.split(/\r?\n/).includes(value)) {
    fs.appendFileSync(exclude, `${content && !content.endsWith('\n') ? '\n' : ''}${value}\n`);
  }
}

async function seedGitRepo(repo, files, { dirtyWorkspace = false } = {}) {
  fs.mkdirSync(repo, { recursive: true });
  const hasGit = fs.existsSync(path.join(repo, '.git'));
  if (!hasGit) await runGit(repo, ['init']);
  await runGit(repo, ['config', 'user.name', 'PiFrame Harness']);
  await runGit(repo, ['config', 'user.email', 'piframe-harness@example.invalid']);
  if (!hasGit) {
    await runGit(repo, ['checkout', '-b', 'main']);
    for (const [relative, content] of Object.entries(files)) {
      const target = path.join(repo, relative);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, content);
    }
    await runGit(repo, ['add', ...Object.keys(files)]);
    await runGit(repo, ['commit', '-m', 'Initial harness fixture']);
  } else {
    try { await runGit(repo, ['checkout', '-f', 'main']); }
    catch { await runGit(repo, ['checkout', '-f', '-b', 'main']); }
    const head = await runGit(repo, ['rev-parse', '--verify', 'HEAD']).then(() => true).catch(() => false);
    if (!head) {
      for (const [relative, content] of Object.entries(files)) {
        const target = path.join(repo, relative);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, content);
      }
      await runGit(repo, ['add', ...Object.keys(files)]);
      await runGit(repo, ['commit', '-m', 'Initial harness fixture']);
    } else {
      await runGit(repo, ['reset', '--hard', 'main']);
    }
  }
  if (dirtyWorkspace) {
    try { await runGit(repo, ['branch', 'feature/demo', 'main']); } catch { }
    await runGit(repo, ['checkout', '-f', 'main']);
    await runGit(repo, ['reset', '--hard', 'main']);
    fs.writeFileSync(path.join(repo, 'notes.md'), `${files['notes.md']}\nStaged harness edit.\n`);
    await runGit(repo, ['add', 'notes.md']);
    fs.writeFileSync(path.join(repo, 'README.md'), `${files['README.md']}\nUnstaged harness edit.\n`);
    fs.writeFileSync(path.join(repo, 'untracked-harness-file.txt'), 'Untracked harness fixture.\n');
  }
  fs.writeFileSync(path.join(repo, '.fake-pi-writable'), 'fake-pi may write files in this fixture.\n');
  appendExclude(repo, '.fake-pi-writable');
}

function writeSessionFixture(sessionsDir, { id, cwd, name, parentSession, count = 3 }) {
  const lines = [
    JSON.stringify({ type: 'session', id, cwd, ...(parentSession ? { parentSession } : {}) }),
    JSON.stringify({ type: 'session_info', name }),
  ];
  for (let index = 0; index < count; index++) {
    lines.push(JSON.stringify({
      type: 'message',
      id: `${id}-message-${index + 1}`,
      message: {
        role: index % 2 === 0 ? 'user' : 'assistant',
        content: `Harness fixture message ${index + 1} for ${name}.`,
        timestamp: new Date(Date.now() - (count - index) * 60_000).toISOString(),
      },
    }));
  }
  fs.writeFileSync(path.join(sessionsDir, `${id}.jsonl`), `${lines.join('\n')}\n`);
}

export async function seedHarnessHome(home, userHome = os.homedir()) {
  const safeHome = assertSafeHome(home, userHome);
  fs.mkdirSync(safeHome, { recursive: true });
  const fixtures = path.join(safeHome, 'fixtures');
  const workspace = path.join(fixtures, 'workspace');
  const secondRepo = path.join(fixtures, 'second-repo');
  const created = [];
  let gitAvailable = true;
  try { await execFileAsync('git', ['--version'], { windowsHide: true }); }
  catch { gitAvailable = false; }
  const workspaceFiles = {
    'README.md': '# Harness workspace\n\nSeeded PiFrame harness repository.\n',
    'notes.md': '# Notes\n\nSeeded Git Changes fixture.\n',
    'src/example.dart': 'void main() {\n  print("PiFrame harness fixture");\n}\n',
  };
  const secondRepoFiles = { 'README.md': '# Second repository\n\nSeeded fixture.\n' };
  fs.mkdirSync(workspace, { recursive: true });
  fs.mkdirSync(secondRepo, { recursive: true });
  if (gitAvailable) {
    try {
      await seedGitRepo(workspace, workspaceFiles, { dirtyWorkspace: true });
      await seedGitRepo(secondRepo, secondRepoFiles);
      created.push('Git repos: fixtures/workspace (staged, unstaged, and untracked changes; feature/demo) and fixtures/second-repo');
    } catch (error) {
      if (/not recognized|not found|enoent/i.test(`${error.message} ${error.code || ''}`)) {
        gitAvailable = false;
      } else throw error;
    }
  }
  if (!gitAvailable) created.push('Git fixtures skipped (git is unavailable)');
  for (const repo of [workspace, secondRepo]) {
    fs.writeFileSync(path.join(repo, '.fake-pi-writable'), 'fake-pi may write files in this fixture.\n');
  }

  const sessionsDir = path.join(safeHome, 'pi-agent', 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });
  writeSessionFixture(sessionsDir, { id: 'harness-workspace-1', cwd: workspace, name: 'Workspace planning', count: 8 });
  writeSessionFixture(sessionsDir, { id: 'harness-workspace-2', cwd: workspace, name: 'Workspace implementation', count: 5 });
  writeSessionFixture(sessionsDir, { id: 'harness-long-history', cwd: workspace, name: 'Long history paging', count: 150 });
  writeSessionFixture(sessionsDir, { id: 'harness-second-repo', cwd: secondRepo, name: 'Second repository review', count: 4 });
  writeSessionFixture(sessionsDir, {
    id: 'harness-worker-child', cwd: workspace, name: 'worker#fixture-child',
    parentSession: 'harness-workspace-1', count: 6,
  });
  created.push('5 Pi session JSONL fixtures (including 150-message history and worker child)');

  const pinsDir = path.join(safeHome, '.piframe');
  fs.mkdirSync(pinsDir, { recursive: true });
  fs.writeFileSync(path.join(pinsDir, 'pinned_sessions.json'), JSON.stringify(['harness-workspace-1'], null, 2));
  created.push('.piframe/pinned_sessions.json pins harness-workspace-1');

  const mcpDir = path.join(safeHome, '.pi', 'agent');
  fs.mkdirSync(mcpDir, { recursive: true });
  fs.writeFileSync(path.join(mcpDir, 'mcp.json'), JSON.stringify({
    mcpServers: {
      'harness-files': { command: 'node', args: ['-e', 'process.exit(0)'], enabled: true },
      'harness-search': { command: 'node', args: ['-e', 'process.exit(0)'], enabled: false },
    },
  }, null, 2));
  created.push('.pi/agent/mcp.json with two MCP server entries');
  console.log(JSON.stringify({ ok: true, home: safeHome, gitAvailable, created }, null, 2));
  return { ok: true, home: safeHome, gitAvailable, created };
}

function prepareHome(home, scenario, size, device, useRealPi) {
  assertSafeHome(home);
  fs.mkdirSync(path.join(home, 'runtime'), { recursive: true });
  fs.mkdirSync(path.join(home, 'pi-agent', 'sessions'), { recursive: true });
  // Deliberately write a clean config. Never copy user's ~/.piframe config or piPath.
  fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify({}), { mode: 0o600 });
  const shim = writeFakePiShims(home);
  writeScenarioControlFile(home, scenario);
  const startedAt = new Date().toISOString();
  const state = {
    runName: path.basename(home), flutterPid: null, wsUri: null, appId: null,
    device, size, scenario, startedAt, ownedPids: [], home, controlPort: null, controlToken: null,
    piShim: shim, realPi: useRealPi,
  };
  writeState(home, state);
  return state;
}

async function refuseRunningWindowsDebug(home) {
  if (process.platform !== 'win32') return;
  const executable = path.resolve(ROOT, 'apps/pi_frame/build/windows/x64/runner/Debug/PiFrame.exe');
  const escaped = executable.replace(/'/g, "''");
  const script = `$target='${escaped}'; $owned=@(${(readState(home)?.ownedPids || []).join(',')}); $all=@(Get-CimInstance Win32_Process); $byId=@{}; foreach($p in $all){$byId[[int]$p.ProcessId]=$p}; $all | Where-Object { if (!$_.ExecutablePath -or $_.ExecutablePath -ine $target) { return $false }; $id=[int]$_.ProcessId; while($id -gt 0){ if($id -in $owned){return $false}; if(!$byId.ContainsKey($id)){break}; $id=[int]$byId[$id].ParentProcessId }; return $true } | Select-Object -ExpandProperty ProcessId`;
  const { stdout } = await execFileAsync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { windowsHide: true });
  if (stdout.trim()) throw new Error(`Refusing to use Flutter's shared Windows Debug build: PiFrame.exe is already running (PID ${stdout.trim()}). Stop that debug session first. Release PiFrame.exe is unaffected.`);
}

function flutterArgs(state) {
  return ['run', '-d', state.device, '-t', 'lib/main_harness.dart', '--machine', `--dart-define=PIFRAME_HARNESS_SIZE=${state.size}`];
}

function addOwned(state, pid) {
  if (pid && !state.ownedPids.includes(pid)) state.ownedPids.push(pid);
}

function startFlutter(home, state) {
  state.piShim = writeFakePiShims(home);
  writeScenarioControlFile(home, state.scenario || 'hello-world');
  const log = fs.createWriteStream(path.join(home, 'flutter.log'), { flags: 'a' });
  const env = {
    ...process.env,
    PI_FRAME_HOME: home,
    PI_FRAME_DAEMON_BIN: path.join(ROOT, 'apps', 'agentd', 'dist', 'pi-agentd.cjs'),
    PI_CODING_AGENT_DIR: path.join(home, 'pi-agent'),
    PI_CODING_AGENT_SESSION_DIR: path.join(home, 'pi-agent', 'sessions'),
    PIFRAME_DEV_LOG: '1',
    FAKE_PI_SCENARIO: state.scenario || 'hello-world',
    FAKE_PI_CONTROL_FILE: path.join(home, 'fake-pi-scenario'),
    HOME: home,
    USERPROFILE: home,
  };
  if (state.realPi) {
    if (process.env.PI_FRAME_PI_PATH) env.PI_FRAME_PI_PATH = process.env.PI_FRAME_PI_PATH;
    else delete env.PI_FRAME_PI_PATH;
    console.warn('\n*** WARNING: --real-pi enabled. Harness will use normal Pi discovery and may run real Pi. ***\n');
  } else {
    env.PI_FRAME_PI_PATH = state.piShim;
  }
  const child = spawn('flutter', flutterArgs(state), {
    cwd: path.join(ROOT, 'apps', 'pi_frame'), env,
    shell: process.platform === 'win32', detached: process.platform !== 'win32',
    windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
  });
  state.flutterPid = child.pid;
  addOwned(state, child.pid);
  writeState(home, state);
  let pending = '';
  const onData = (chunk) => {
    log.write(chunk);
    pending += chunk.toString();
    let newline;
    while ((newline = pending.indexOf('\n')) >= 0) {
      const line = pending.slice(0, newline).trim();
      pending = pending.slice(newline + 1);
      try {
        const parsed = JSON.parse(line);
        for (const event of Array.isArray(parsed) ? parsed : [parsed]) {
          if (event?.event === 'app.debugPort') state.wsUri = event.params?.wsUri || state.wsUri;
          if (event?.event === 'app.started') state.appId = event.params?.appId || state.appId;
        }
        if (state.wsUri || state.appId) writeState(home, state);
      } catch { }
    }
  };
  child.stdout.on('data', onData);
  child.stderr.on('data', onData);
  child.on('error', (error) => { log.write(`\n[flutter spawn error] ${error.stack || error}\n`); });
  child.on('exit', (code) => {
    log.write(`\n[flutter exited code=${code}]\n`);
    if (state.flutterPid === child.pid) {
      state.flutterPid = null;
      state.wsUri = null;
      state.appId = null;
      writeState(home, state);
    }
  });
  child.stdin.on('error', () => {});
  state.flutterChild = child;
  return child;
}

async function stopFlutter(home, state) {
  const child = state.flutterChild;
  if (child && child.stdin && state.appId) {
    try { child.stdin.write(`${JSON.stringify([{ id: Date.now(), method: 'app.stop', params: { appId: state.appId } }])}\n`); } catch { }
  }
  const pid = state.flutterPid;
  if (pid && state.ownedPids.includes(pid)) {
    await killOwned(pid, home, { tree: true });
    await new Promise((resolve) => setTimeout(resolve, 600));
  }
  state.flutterPid = null;
  state.wsUri = null;
  state.appId = null;
  writeState(home, state);
}

async function controlServer(home, state) {
  const server = await import('node:http').then(({ createServer }) => createServer(async (req, res) => {
    if (req.method !== 'POST' || req.url !== '/control') { res.writeHead(404).end(); return; }
    let body = '';
    for await (const chunk of req) body += chunk;
    try {
      const command = JSON.parse(body);
      if (command.token !== state.controlToken) { res.writeHead(403).end(); return; }
      if (command.method === 'status') {
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: true, flutterPid: state.flutterPid, wsUri: state.wsUri }));
        return;
      } else if (command.method === 'reload' || command.method === 'restart') {
        if (!state.flutterChild || !state.appId) throw new Error('Flutter app is not ready');
        const id = Date.now();
        const fullRestart = command.method === 'restart';
        state.flutterChild.stdin.write(`${JSON.stringify([{ id, method: 'app.restart', params: { appId: state.appId, fullRestart } }])}\n`);
      } else if (command.method === 'shutdownApp') {
        await stopFlutter(home, state);
      } else if (command.method === 'rebuild') {
        await stopFlutter(home, state);
        startFlutter(home, state);
      } else if (command.method === 'stop') {
        await stopFlutter(home, state);
        const pid = daemonPid(home);
        if (pid) await killOwned(pid, home, { daemon: true });
      } else throw new Error(`Unknown control method: ${command.method}`);
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: true }));
    } catch (error) {
      res.writeHead(500, { 'content-type': 'application/json' }).end(JSON.stringify({ error: error.message }));
    }
  }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  state.controlPort = server.address().port;
  state.controlToken = crypto.randomBytes(24).toString('hex');
  state.supervisorPid = process.pid;
  addOwned(state, process.pid);
  writeState(home, state);
  return server;
}

async function requestControl(state, method) {
  if (!state?.controlPort || !state.controlToken) throw new Error('No live harness supervisor found');
  const response = await fetch(`http://127.0.0.1:${state.controlPort}/control`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ token: state.controlToken, method }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Supervisor control failed (${response.status})`);
  return data;
}

async function supervise(home, device, size, scenario, realPi) {
  assertSafeHome(home);
  const state = readState(home) || prepareHome(home, scenario, size, device, realPi);
  state.home = home;
  state.device = device || state.device;
  state.size = size || state.size;
  state.scenario = scenario || state.scenario || 'hello-world';
  state.realPi = Boolean(realPi || state.realPi);
  const server = await controlServer(home, state);
  startFlutter(home, state);
  const shutdown = async () => {
    await stopFlutter(home, state).catch(() => {});
    const daemon = daemonPid(home);
    if (daemon) await killOwned(daemon, home, { daemon: true }).catch(() => {});
    server.close();
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
  // Keep the process alive for the local control endpoint.
}

class VmClient {
  constructor(uri) { this.uri = uri; this.socket = null; this.seq = 1; this.waiters = new Map(); }
  async connect() {
    if (typeof WebSocket === 'undefined') throw new Error('Node 22+ global WebSocket is required');
    this.socket = new WebSocket(this.uri);
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Dart VM websocket connection timed out')), 10_000);
      this.socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
      this.socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('Dart VM websocket connection failed')); }, { once: true });
    });
    this.socket.addEventListener('message', (event) => {
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      const waiter = this.waiters.get(message.id);
      if (waiter) { this.waiters.delete(message.id); message.error ? waiter.reject(new Error(message.error.message || JSON.stringify(message.error))) : waiter.resolve(message.result); }
    });
    this.socket.addEventListener('close', () => {
      for (const waiter of this.waiters.values()) waiter.reject(new Error('Dart VM websocket closed'));
      this.waiters.clear();
    });
  }
  call(method, params = {}) {
    const id = this.seq++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.waiters.delete(id); reject(new Error(`Dart VM call timed out: ${method}`)); }, 15_000);
      this.waiters.set(id, { resolve: (value) => { clearTimeout(timer); resolve(value); }, reject: (error) => { clearTimeout(timer); reject(error); } });
      this.socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  }
  close() { try { this.socket?.close(); } catch { } }
}

async function invokeExtension(state, extension, params = {}) {
  if (!state?.wsUri) throw new Error('No Dart VM websocket URI. Start the harness first.');
  const client = new VmClient(state.wsUri);
  try {
    await client.connect();
    const vm = await client.call('getVM');
    for (const isolate of vm.isolates || []) {
      const details = await client.call('getIsolate', { isolateId: isolate.id });
      if (!(details.extensionRPCs || []).includes('ext.piframe.ping')) continue;
      const encoded = encodeParams(params);
      return await client.call('ext.piframe.' + extension, { isolateId: isolate.id, ...encoded });
    }
    throw new Error('No isolate advertises ext.piframe.ping');
  } finally { client.close(); }
}

async function waitReady(home, timeout = DEFAULT_TIMEOUT) {
  const end = Date.now() + timeout;
  let lastError;
  while (Date.now() < end) {
    const state = readState(home);
    if (state?.wsUri) {
      try {
        await invokeExtension(state, 'ping');
        return state;
      } catch (error) { lastError = error; }
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Harness did not become ready in ${Math.round(timeout / 1000)}s${lastError ? `: ${lastError.message}` : ''}. See ${path.join(home, 'flutter.log')}`);
}

async function launchSupervisor(home, state) {
  const args = [SCRIPT, '__supervise', '--home', home, '--device', state.device, '--size', state.size, '--scenario', state.scenario];
  if (state.realPi) args.push('--real-pi');
  const child = spawn(process.execPath, args, { cwd: ROOT, detached: true, stdio: 'ignore', windowsHide: true });
  child.unref();
  // Supervisor writes its own PID; parent records only as a fallback until then.
}

async function startCommand(options) {
  const runName = options.run || 'default';
  const home = runDir(runName);
  writeFakePiShims(home);
  const device = options.device || (process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'macos' : 'linux');
  const size = options.size || '1280x800';
  const scenario = validateScenarioName(options.scenario || 'hello-world');
  if (!/^\d+x\d+$/.test(size)) throw new Error(`Invalid size: ${size}`);
  if (!['windows', 'macos', 'linux'].includes(device)) throw new Error(`Unsupported desktop device: ${device}`);
  if (options.seed) await seedHarnessHome(home);
  const previous = readState(home);
  if (previous?.controlPort) {
    try {
      const status = await fetch(`http://127.0.0.1:${previous.controlPort}/control`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token: previous.controlToken, method: 'status' }) });
      if (status.status === 200) { console.log(JSON.stringify({ ok: true, run: runName, wsUri: previous.wsUri, home, alreadyRunning: true })); return; }
    } catch { }
  }
  if (previous) await stopRun(runName);
  await refuseRunningWindowsDebug(home);
  if (options['real-pi']) console.warn('*** WARNING: --real-pi enabled. Harness may invoke a real Pi binary; its environment remains isolated to this run. ***');
  await ensureBuilds(Boolean(options['no-daemon-build']));
  const state = prepareHome(home, scenario, size, device, Boolean(options['real-pi']));
  await launchSupervisor(home, state);
  const ready = await waitReady(home);
  console.log(JSON.stringify({ ok: true, run: runName, wsUri: ready.wsUri, home }));
}

function requireState(runName = 'default') {
  const home = runDir(runName);
  const state = readState(home);
  if (!state) throw new Error(`Harness run not found: ${runName}`);
  return { home, state };
}

async function callCommand(extension, rawParams, runName) {
  const { state } = requireState(runName);
  const params = rawParams ? JSON.parse(rawParams) : {};
  console.log(JSON.stringify(await invokeExtension(state, extension, params), null, 2));
}

function selectorParams(selector) {
  const parsed = parseSelector(selector);
  return { [parsed.type]: parsed.value, ...(parsed.index === undefined ? {} : { index: parsed.index }) };
}

async function convenience(command, positional, options, runName) {
  const { state } = requireState(runName);
  let ext, params = {};
  if (command === 'tap' || command === 'hover' || command === 'longPress' || command === 'rightClick' || command === 'doubleTap') {
    ext = command;
    params = selectorParams(positional[0]);
  }
  else if (command === 'tapAt') { ext = 'tapAt'; params = { x: positional[0], y: positional[1] }; }
  else if (command === 'drag') { ext = 'drag'; params = { ...selectorParams(positional[0]), dx: positional[1], dy: positional[2] }; }
  else if (command === 'type') { ext = 'enterText'; params = { value: positional[0] }; if (options.into) Object.assign(params, selectorParams(options.into)); }
  else if (command === 'key') { ext = 'sendKey'; params = { key: positional[0], ctrl: !!options.ctrl, shift: !!options.shift, alt: !!options.alt, meta: !!options.meta }; }
  else if (command === 'scroll') { ext = 'scroll'; params = { ...selectorParams(positional[0]), dx: 0, dy: Number(positional[1]) }; }
  else if (command === 'tree') {
    ext = 'tree';
    if (options.filter) params.filter = options.filter;
    if (options.limit !== undefined) params.maxEntries = Number(options.limit);
    if (options.depth !== undefined) params.maxDepth = Number(options.depth);
  }
  else if (command === 'media') {
    ext = 'media';
    if (options['text-scale'] !== undefined) params.textScale = options['text-scale'];
    if (options['reduce-motion'] !== undefined) params.reduceMotion = options['reduce-motion'];
    if (options.brightness !== undefined) params.brightness = options.brightness;
    if (options.reset) params.reset = true;
  }
  else if (command === 'state') ext = 'state';
  else if (command === 'resize') { ext = 'resize'; const [width, height] = String(positional[0] || '').split('x').map(Number); params = { width, height }; }
  else if (command === 'shot') {
    ext = 'screenshot';
    const label = (positional[0] || 'shot').replace(/[^a-zA-Z0-9._-]+/g, '-');
    const output = options.out ? path.resolve(options.out) : path.join(ROOT, 'scratch', 'harness', runName, `${new Date().toISOString().replace(/[:.]/g, '-')}-${label}.png`);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    params = { path: output };
    const result = await invokeExtension(state, ext, params);
    console.log(output);
    if (result !== undefined) console.log(JSON.stringify(result, null, 2));
    return;
  }
  if (['tap', 'hover', 'longPress', 'rightClick', 'doubleTap', 'type', 'key', 'scroll', 'drag'].includes(command) && !positional[0]) {
    throw new Error(`Missing argument for ${command}`);
  }
  if (command === 'tapAt') {
    const x = Number(positional[0]); const y = Number(positional[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error('tapAt expects numeric x and y');
  }
  if (command === 'drag' && (!Number.isFinite(Number(positional[1])) || !Number.isFinite(Number(positional[2])))) {
    throw new Error('drag expects selector dx dy with numeric offsets');
  }
  if (command === 'scroll' && !Number.isFinite(params.dy)) throw new Error('scroll dy must be a number');
  if (command === 'tree') {
    if (options.limit !== undefined && (!Number.isInteger(params.maxEntries) || params.maxEntries < 1)) throw new Error('--limit must be a positive integer');
    if (options.depth !== undefined && (!Number.isInteger(params.maxDepth) || params.maxDepth < 0)) throw new Error('--depth must be a non-negative integer');
  }
  if (command === 'media') {
    if (options['text-scale'] !== undefined && (!Number.isFinite(Number(options['text-scale'])) || Number(options['text-scale']) <= 0)) throw new Error('--text-scale must be a positive number');
    if (options['reduce-motion'] !== undefined && !['on', 'off'].includes(options['reduce-motion'])) throw new Error('--reduce-motion must be on or off');
    if (options.brightness !== undefined && !['light', 'dark'].includes(options.brightness)) throw new Error('--brightness must be light or dark');
    if (!options.reset && Object.keys(options).every((key) => key === 'run')) throw new Error('media needs an override or --reset');
  }
  if (command === 'resize' && (!Number.isInteger(params.width) || !Number.isInteger(params.height))) throw new Error('resize expects WxH');
  console.log(JSON.stringify(await invokeExtension(state, ext, params), null, 2));
}

async function tailFile(file, lines) {
  try {
    const content = fs.readFileSync(file, 'utf8').trimEnd().split(/\r?\n/);
    return content.slice(-lines).join('\n');
  } catch { return `[missing] ${file}`; }
}

async function stopRun(runName) {
  const { home, state } = requireState(runName);
  if (state.controlPort) await requestControl(state, 'stop').catch(() => {});
  const refreshed = readState(home) || state;
  if (refreshed.flutterPid && refreshed.ownedPids?.includes(refreshed.flutterPid)) {
    await killOwned(refreshed.flutterPid, home, { tree: true }).catch(() => {});
  }
  const supervisorPid = refreshed.supervisorPid;
  if (supervisorPid) await killOwned(supervisorPid, home, { tree: false }).catch(() => {});
  const daemon = daemonPid(home);
  if (daemon) await killOwned(daemon, home, { daemon: true }).catch(() => {});
  console.log(JSON.stringify({ ok: true, run: runName, stopped: true }));
}

async function stopAll() {
  let runs = [];
  try { runs = fs.readdirSync(HARNESS_ROOT, { withFileTypes: true }).filter((entry) => entry.isDirectory() && fs.existsSync(path.join(HARNESS_ROOT, entry.name, 'harness.json'))).map((entry) => entry.name); } catch { }
  for (const run of runs) await stopRun(run);
}

async function main(argv) {
  const command = argv[0];
  const { positional, options } = parseArgs(argv.slice(1));
  const runName = options.run || 'default';
  if (!command || command === 'help' || command === '--help') {
    console.log('Usage: pnpm harness <start|seed|scenarios|scenario|call|tap|tapAt|rightClick|doubleTap|drag|longPress|hover|type|key|scroll|tree|media|state|resize|shot|reload|restart|rebuild|logs|status|stop> [options]'); return;
  }
  if (command === '__supervise') {
    const home = options.home;
    if (!home) throw new Error('Missing supervisor home');
    await supervise(path.resolve(home), options.device, options.size, options.scenario, Boolean(options['real-pi']));
    return;
  }
  if (command === 'start') return startCommand(options);
  if (command === 'seed') return seedHarnessHome(runDir(runName));
  if (command === 'scenarios') {
    console.log(JSON.stringify(listScenarios(), null, 2));
    return;
  }
  if (command === 'scenario') {
    const scenario = validateScenarioName(positional[0]);
    const { home, state } = requireState(runName);
    writeScenarioControlFile(home, scenario);
    state.scenario = scenario;
    writeState(home, state);
    console.log(JSON.stringify({ ok: true, scenario }));
    return;
  }
  if (command === 'call') return callCommand(positional[0], positional[1], runName);
  if (['tap', 'tapAt', 'rightClick', 'doubleTap', 'drag', 'longPress', 'hover', 'type', 'key', 'scroll', 'tree', 'media', 'state', 'resize', 'shot'].includes(command)) return convenience(command, positional, options, runName);
  if (['reload', 'restart'].includes(command)) {
    const { state } = requireState(runName);
    await requestControl(state, command);
    console.log(JSON.stringify({ ok: true, run: runName, action: command })); return;
  }
  if (command === 'rebuild') {
    const { home, state } = requireState(runName);
    await refuseRunningWindowsDebug(home);
    if (options.daemon) {
      await requestControl(state, 'shutdownApp');
      await ensureBuilds(false, true);
      const pid = daemonPid(home);
      if (pid) await killOwned(pid, home, { daemon: true });
    }
    const refreshed = readState(home) || state;
    await requestControl(refreshed, 'rebuild');
    const ready = await waitReady(home);
    console.log(JSON.stringify({ ok: true, run: runName, wsUri: ready.wsUri, rebuilt: true })); return;
  }
  if (command === 'logs') {
    const { home } = requireState(runName); const count = Number(options.lines || 100);
    if (!Number.isInteger(count) || count < 1) throw new Error('--lines must be a positive integer');
    console.log('--- flutter.log ---\n' + await tailFile(path.join(home, 'flutter.log'), count));
    console.log('--- daemon.log ---\n' + await tailFile(path.join(home, 'runtime', 'daemon.log'), count)); return;
  }
  if (command === 'status') {
    const { state } = requireState(runName);
    let live = false;
    try { const r = await fetch(`http://127.0.0.1:${state.controlPort}/control`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token: state.controlToken, method: 'status' }) }); live = r.status !== 404; } catch { }
    console.log(JSON.stringify({ ...state, live }, null, 2)); return;
  }
  if (command === 'stop') return options.all ? stopAll() : stopRun(runName);
  throw new Error(`Unknown command: ${command}`);
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main(process.argv.slice(2)).catch((error) => { console.error(`pf-harness: ${error.message}`); process.exitCode = 1; });
}

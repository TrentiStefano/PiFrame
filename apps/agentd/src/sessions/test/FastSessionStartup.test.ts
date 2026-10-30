import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { SessionIndex, type SessionSummary } from '../SessionIndex.js';
import { SessionRegistry } from '../SessionRegistry.js';

const journalRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-journal-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = journalRoot;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(journalRoot, { recursive: true, force: true });
});

function makeRegistry(index: SessionIndex, broadcast: (sessionId: string, event: any) => void) {
  return new SessionRegistry({
    piExecutablePath: process.execPath,
    capabilities: { version: '0.99.2', supported: true, modes: ['rpc'], features: [] },
    workerIdleTimeoutMs: 0,
    connectionManager: { broadcast } as any,
    sessionIndex: index,
    checkTerminalOwner: async () => false,
  });
}

function waitForEvent() {
  let resolve!: (event: any) => void;
  const promise = new Promise<any>((done) => { resolve = done; });
  return { promise, resolve };
}

test('cold listing returns provisional title and later publishes the exact historical title', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-list-'));
  const dir = path.join(root, 'sessions');
  const cache = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'timestamp_fast-id.jsonl');
  const rows = [
    { type: 'session', id: 'fast-id', cwd: process.cwd() },
    { type: 'message', message: { role: 'user', content: 'a'.repeat(100_000) } },
    { type: 'session_info', name: 'The exact title' },
    { type: 'message', message: { role: 'assistant', content: 'b'.repeat(100_000) } },
  ];
  const contents = rows.map((row) => JSON.stringify(row)).join('\n') + '\n';
  fs.writeFileSync(file, contents);
  const event = waitForEvent();
  const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
  const registry = makeRegistry(index, (_sessionId, message) => {
    if (message.type === 'session.indexChanged') event.resolve(message);
  });
  try {
    const first = await registry.listSessions();
    assert.equal(first.length, 1);
    assert.equal(first[0].id, 'fast-id');
    assert.equal(first[0].cwd, process.cwd());
    assert.notEqual(first[0].name, 'The exact title');
    assert.equal(first[0].messageCount, undefined);
    const changed = await event.promise;
    assert.equal(changed.sessionId, '@daemon');
    const final = await registry.listSessions();
    assert.equal(final[0].name, 'The exact title');
    assert.equal(final[0].messageCount, 2);
    assert.equal(fs.readFileSync(file, 'utf8'), contents);
    const warm = new SessionIndex({ sessionsDir: dir, cachePath: cache });
    const fast = await warm.scanFast();
    assert.equal(fast.sessions[0].name, 'The exact title');
    assert.equal(fast.needsRefresh, false);
  } finally {
    await registry.closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('session.list returns cached rows while filesystem revalidation continues', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-cached-list-'));
  const dir = path.join(root, 'sessions');
  const cache = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'cached.jsonl'), [
    { type: 'session', id: 'cached', cwd: process.cwd() },
    { type: 'session_info', name: 'Cached session' },
  ].map((row) => JSON.stringify(row)).join('\n') + '\n');
  try {
    await new SessionIndex({ sessionsDir: dir, cachePath: cache }).scan();
    const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
    const enumerate = (index as any).enumerateSessionFiles.bind(index);
    let release!: () => void;
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    (index as any).enumerateSessionFiles = async () => {
      await blocked;
      return enumerate();
    };
    const registry = makeRegistry(index, () => {});
    try {
      const listed = await Promise.race([
        registry.listSessions(),
        new Promise<never>((_, reject) => setTimeout(() => reject(new Error('list waited for filesystem')), 100)),
      ]);
      assert.equal(listed[0].id, 'cached');
      release();
      await index.scanFast();
    } finally {
      release();
      await registry.closeAll();
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('fast refresh publishes changed visible rows', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'Old name', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false,
  };
  const event = waitForEvent();
  const index = {
    getCachedSnapshot: () => [row],
    scanFast: async () => ({ sessions: [{ ...row, name: 'New name' }], needsRefresh: false }),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => event.resolve(message));
  try {
    assert.equal((await registry.listSessions())[0].name, 'Old name');
    assert.equal((await event.promise).payload.updated[0].name, 'New name');
  } finally {
    await registry.closeAll();
  }
});

test('fast refresh does not invalidate for hidden subsessions', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'Visible', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false,
  };
  const subsession: SessionSummary = {
    ...row, id: 'child', sessionFile: 'child.jsonl', isSubsession: true,
  };
  const events: unknown[] = [];
  const index = {
    getCachedSnapshot: () => [row],
    scanFast: async () => ({ sessions: [row, subsession], needsRefresh: false }),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => events.push(message));
  try {
    assert.equal((await registry.listSessions()).length, 1);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(events.length, 0);
  } finally {
    await registry.closeAll();
  }
});

test('cold session.list bounds its filesystem wait and continues discovery', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-cold-list-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'new.jsonl'), JSON.stringify({
    type: 'session', id: 'new', cwd: process.cwd(),
  }) + '\n');
  const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
  const enumerate = (index as any).enumerateSessionFiles.bind(index);
  let release!: () => void;
  const blocked = new Promise<void>((resolve) => { release = resolve; });
  (index as any).enumerateSessionFiles = async () => {
    await blocked;
    return enumerate();
  };
  const registry = makeRegistry(index, () => {});
  try {
    const listed = await Promise.race([
      registry.listSessions(),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error('cold session.list waited for filesystem')), 1500)),
    ]);
    assert.deepEqual(listed, []);
    release();
    assert.equal((await index.scanFast()).sessions[0].id, 'new');
  } finally {
    release();
    await registry.closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('refresh detects renamed files, removed files and cached temporary children', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-refresh-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const parent = path.join(dir, 'parent.jsonl');
  const child = path.join(dir, 'child.jsonl');
  fs.writeFileSync(parent, [
    { type: 'session', id: 'parent', cwd: process.cwd() },
    { type: 'session_info', name: 'Old name' },
  ].map((row) => JSON.stringify(row)).join('\n') + '\n');
  fs.writeFileSync(child, [
    { type: 'session', id: 'child', cwd: path.join(os.tmpdir(), 'worker'), parentSession: parent },
    { type: 'session_info', name: 'worker#abc' },
  ].map((row) => JSON.stringify(row)).join('\n') + '\n');
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    assert.equal((await index.scan()).length, 2);
    const cached = await index.scanFast();
    assert.equal(cached.needsRefresh, false);
    assert.ok(cached.sessions.some((row) => row.id === 'child' && row.isSubsession));
    fs.appendFileSync(parent, JSON.stringify({ type: 'session_info', name: 'New name' }) + '\n');
    const now = new Date(Date.now() + 2_000);
    fs.utimesSync(parent, now, now);
    assert.equal((await index.scanFast()).needsRefresh, true);
    await index.scan();
    const updated = await index.scanFast();
    assert.equal(updated.sessions.find((row) => row.id === 'parent')?.name, 'New name');
    assert.equal(updated.needsRefresh, false);
    const oldStat = fs.statSync(parent);
    fs.appendFileSync(parent, JSON.stringify({ type: 'session_info', name: 'Latest name' }) + '\n');
    fs.utimesSync(parent, oldStat.atime, oldStat.mtime);
    assert.equal(fs.statSync(parent).mtimeMs, oldStat.mtimeMs);
    assert.equal((await index.scanFast()).needsRefresh, true);
    await index.scan();
    assert.equal((await index.scanFast()).sessions.find((row) => row.id === 'parent')?.name, 'Latest name');
    fs.appendFileSync(parent, JSON.stringify({ type: 'session_info' }) + '\n');
    await index.scan();
    assert.equal((await index.scanFast()).sessions.find((row) => row.id === 'parent')?.name, undefined);
    fs.unlinkSync(child);
    assert.ok(!(await index.scanFast()).sessions.some((row) => row.id === 'child'));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('legacy cache titles remain visible while their metadata is revalidated', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-index-upgrade-'));
  const dir = path.join(root, 'sessions');
  const cachePath = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'session.jsonl'), [
    { type: 'session', id: 'one', cwd: process.cwd() },
    { type: 'session_info', name: 'Indexed title' },
  ].map((row) => JSON.stringify(row)).join('\n') + '\n');
  try {
    await new SessionIndex({ sessionsDir: dir, cachePath }).scan();
    const legacy = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    delete legacy[0].ctime;
    fs.writeFileSync(cachePath, JSON.stringify(legacy));
    const index = new SessionIndex({ sessionsDir: dir, cachePath });
    const first = await index.scanFast();
    assert.equal(first.sessions[0].name, 'Indexed title');
    assert.equal(first.needsRefresh, true);
    let parses = 0;
    const parse = (index as any).parseSessionFileAsync.bind(index);
    (index as any).parseSessionFileAsync = (...args: unknown[]) => { parses++; return parse(...args); };
    await index.scan();
    assert.equal(parses, 1);
    assert.equal((await index.scanFast()).needsRefresh, false);
    assert.equal(typeof JSON.parse(fs.readFileSync(cachePath, 'utf8'))[0].ctime, 'number');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('legacy cache revalidation detects rewrites with unchanged size and mtime', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-legacy-change-'));
  const dir = path.join(root, 'sessions');
  const cachePath = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'session.jsonl');
  const header = JSON.stringify({ type: 'session', id: 'one', cwd: process.cwd() }) + '\n';
  const text = (name: string) => header + JSON.stringify({ type: 'session_info', name }) + '\n';
  fs.writeFileSync(file, text('Old name'));
  const stableTime = new Date(Date.now() - 10_000);
  fs.utimesSync(file, stableTime, stableTime);
  try {
    await new SessionIndex({ sessionsDir: dir, cachePath }).scan();
    const old = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    delete old[0].ctime;
    fs.writeFileSync(cachePath, JSON.stringify(old));
    fs.writeFileSync(file, text('New name'));
    fs.utimesSync(file, stableTime, stableTime);
    const index = new SessionIndex({ sessionsDir: dir, cachePath });
    const first = await index.scanFast();
    assert.equal(first.sessions[0].name, 'Old name');
    assert.equal(first.needsRefresh, true);
    await index.scan();
    assert.equal((await index.scanFast()).sessions[0].name, 'New name');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('same-size rewrites with restored mtime invalidate the cached title', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-index-ctime-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'session.jsonl');
  const header = JSON.stringify({ type: 'session', id: 'one', cwd: process.cwd() }) + '\n';
  const text = (name: string) => header + JSON.stringify({ type: 'session_info', name }) + '\n';
  fs.writeFileSync(file, text('Old name'));
  const stableTime = new Date(Date.now() - 10_000);
  fs.utimesSync(file, stableTime, stableTime);
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    await index.scan();
    const before = fs.statSync(file);
    await new Promise((resolve) => setTimeout(resolve, 20));
    fs.writeFileSync(file, text('New name'));
    fs.utimesSync(file, before.atime, before.mtime);
    const after = fs.statSync(file);
    assert.equal(after.size, before.size);
    assert.equal(after.mtimeMs, before.mtimeMs);
    assert.notEqual(after.ctimeMs, before.ctimeMs);
    assert.equal((await index.scanFast()).needsRefresh, true);
    await index.scan();
    assert.equal((await index.scanFast()).sessions[0].name, 'New name');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('a cached file changed during fast discovery is marked for refresh', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-changing-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'session.jsonl');
  fs.writeFileSync(file, JSON.stringify({ type: 'session', id: 'one', cwd: process.cwd() }) + '\n');
  const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
  const original = fs.promises.stat;
  try {
    await index.scan();
    let changed = false;
    (fs.promises as any).stat = async (...args: Parameters<typeof fs.promises.stat>) => {
      const stat = await original(...args);
      if (!changed && args[0] === file) {
        changed = true;
        fs.appendFileSync(file, JSON.stringify({ type: 'session_info', name: 'New name' }) + '\n');
      }
      return stat;
    };
    const result = await index.scanFast();
    assert.equal(changed, true);
    assert.equal(result.needsRefresh, true);
  } finally {
    (fs.promises as any).stat = original;
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('a session changed during indexing is refreshed after the write settles', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-index-changing-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'changing.jsonl');
  fs.writeFileSync(file, JSON.stringify({ type: 'session', id: 'changing', cwd: process.cwd() }) + '\n');
  const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
  const parse = (index as any).parseSessionFileAsync.bind(index);
  let changed = false;
  (index as any).parseSessionFileAsync = async (...args: unknown[]) => {
    const summary = await parse(...args);
    if (!changed) {
      changed = true;
      fs.appendFileSync(file, JSON.stringify({ type: 'session_info', name: 'Final name' }) + '\n');
    }
    return summary;
  };
  const event = waitForEvent();
  const registry = makeRegistry(index, (_sessionId, message) => {
    if (message.type === 'session.indexChanged' && message.payload.updated) event.resolve(message);
  });
  try {
    assert.equal((await registry.listSessions())[0].id, 'changing');
    await event.promise;
    assert.equal((await registry.listSessions())[0].name, 'Final name');
  } finally {
    await registry.closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('discovery follows a linked session directory', { timeout: 10_000 }, async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-index-link-'));
  const dir = path.join(root, 'sessions');
  const target = path.join(root, 'target');
  fs.mkdirSync(dir);
  fs.mkdirSync(target);
  fs.writeFileSync(path.join(target, 'linked.jsonl'), JSON.stringify({ type: 'session', id: 'linked', cwd: process.cwd() }) + '\n');
  try {
    try {
      fs.symlinkSync(target, path.join(dir, 'link'), process.platform === 'win32' ? 'junction' : 'dir');
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'EPERM') { t.skip('link creation is not permitted'); return; }
      throw error;
    }
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    assert.equal((await index.scanFast()).sessions[0].id, 'linked');
    assert.equal((await index.scan())[0].id, 'linked');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('full indexing yields to the event loop while a transcript is read', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-index-yield-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'large.jsonl');
  const message = JSON.stringify({ type: 'message', message: { role: 'user', content: 'a'.repeat(4_000) } });
  fs.writeFileSync(file, JSON.stringify({ type: 'session', id: 'large', cwd: process.cwd() }) + '\n' + (message + '\n').repeat(2_000));
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    let turns = 0;
    let running = true;
    const heartbeat = (async () => {
      while (running) {
        await new Promise<void>((resolve) => setImmediate(resolve));
        turns++;
      }
    })();
    let rows: SessionSummary[];
    try {
      rows = await index.scan();
    } finally {
      running = false;
      await heartbeat;
    }
    assert.equal(rows[0].messageCount, 2_000);
    assert.ok(turns > 1, 'indexing must let other event-loop work run');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('a provisional row can be explicitly deleted before the full scan', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-delete-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const file = path.join(dir, 'timestamp_delete-id.jsonl');
  fs.writeFileSync(file, JSON.stringify({ type: 'session', id: 'delete-id', cwd: process.cwd() }) + '\n');
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    const first = await index.scanFast();
    assert.equal(first.sessions[0].id, 'delete-id');
    assert.equal(index.removeSession('delete-id'), file);
    assert.equal(fs.existsSync(file), false);
    assert.equal((await index.scanFast()).sessions.length, 0);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('uncached subagent description is recovered from a long message', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-child-preview-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  const parent = path.join(dir, 'parent.jsonl');
  const child = path.join(dir, 'child.jsonl');
  fs.writeFileSync(parent, JSON.stringify({ type: 'session', id: 'parent', cwd: process.cwd() }) + '\n');
  fs.writeFileSync(child, [
    { type: 'session', id: 'child', cwd: process.cwd(), parentSession: parent },
    { type: 'message', message: { role: 'user', content: 'a'.repeat(100_000) } },
  ].map((row) => JSON.stringify(row)).join('\n') + '\n');
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    const result = await index.getSubagents('parent', parent);
    assert.equal(result.length, 1);
    assert.equal(result[0].description, 'a'.repeat(100));
    assert.equal(result[0].output, 'a'.repeat(100));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('concurrent fast discovery shares filesystem work but keeps active flags per caller', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-shared-'));
  const dir = path.join(root, 'sessions');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'session.jsonl'), JSON.stringify({ type: 'session', id: 'one', cwd: process.cwd() }) + '\n');
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: path.join(root, 'index.json') });
    const enumerate = (index as any).enumerateSessionFiles.bind(index);
    let calls = 0;
    (index as any).enumerateSessionFiles = () => { calls++; return enumerate(); };
    const [active, inactive] = await Promise.all([index.scanFast(new Set(['one'])), index.scanFast()]);
    assert.equal(calls, 1);
    assert.equal(active.sessions[0].isActive, true);
    assert.equal(inactive.sessions[0].isActive, false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('fast discovery cannot erase a row added by an overlapping authoritative scan', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-overlapping-index-'));
  const dir = path.join(root, 'sessions');
  const cache = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'first.jsonl'), JSON.stringify({
    type: 'session', id: 'first', cwd: process.cwd(),
  }) + '\n');
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
    await index.scan();
    const enumerate = (index as any).enumerateSessionFiles.bind(index);
    const fastFiles = await enumerate();
    fs.writeFileSync(path.join(dir, 'second.jsonl'), JSON.stringify({
      type: 'session', id: 'second', cwd: process.cwd(),
    }) + '\n');
    let release!: () => void;
    let started!: () => void;
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    const fastStarted = new Promise<void>((resolve) => { started = resolve; });
    let calls = 0;
    (index as any).enumerateSessionFiles = async () => {
      if (++calls === 1) {
        started();
        await blocked;
        return fastFiles;
      }
      return enumerate();
    };
    const fast = index.scanFast();
    await fastStarted;
    await index.scan();
    release();
    const result = await fast;
    assert.equal(result.needsRefresh, true);
    assert.deepEqual(index.getCachedSnapshot().map((row) => row.id).sort(), ['first', 'second']);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('fast enumeration preserves a snapshot row resolved concurrently', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-snapshot-race-'));
  const dir = path.join(root, 'sessions');
  const cache = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'first.jsonl'), JSON.stringify({
    type: 'session', id: 'first', cwd: process.cwd(),
  }) + '\n');
  let release!: () => void;
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
    await index.scan();
    await index.scanFast();
    let started!: () => void;
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    const fastStarted = new Promise<void>((resolve) => { started = resolve; });
    (index as any).enumerateSessionFiles = async () => {
      started();
      await blocked;
      return [];
    };
    const fast = index.scanFast();
    await fastStarted;
    assert.equal((await index.resolveFast('first'))?.id, 'first');
    release();
    assert.equal((await fast).needsRefresh, true);
    assert.equal(index.getCachedSnapshot()[0].id, 'first');
  } finally {
    release();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('fast ENOENT does not clear cache rows added by an overlapping full scan', { timeout: 10_000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-fast-enoent-race-'));
  const dir = path.join(root, 'sessions');
  const cache = path.join(root, 'index.json');
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'first.jsonl'), JSON.stringify({
    type: 'session', id: 'first', cwd: process.cwd(),
  }) + '\n');
  let release!: () => void;
  try {
    const index = new SessionIndex({ sessionsDir: dir, cachePath: cache });
    await index.scan();
    await index.scanFast();
    const enumerate = (index as any).enumerateSessionFiles.bind(index);
    fs.writeFileSync(path.join(dir, 'second.jsonl'), JSON.stringify({
      type: 'session', id: 'second', cwd: process.cwd(),
    }) + '\n');
    let started!: () => void;
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    const fastStarted = new Promise<void>((resolve) => { started = resolve; });
    let calls = 0;
    (index as any).enumerateSessionFiles = async () => {
      if (++calls === 1) {
        started();
        await blocked;
        throw Object.assign(new Error('session directory vanished'), { code: 'ENOENT' });
      }
      return enumerate();
    };
    const fast = index.scanFast();
    await fastStarted;
    await index.scan();
    release();
    const result = await fast;
    assert.equal(result.needsRefresh, true);
    assert.deepEqual(index.getCachedSnapshot().map((row) => row.id).sort(), ['first', 'second']);
  } finally {
    release?.();
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('opening a pinned session before listing uses fast discovery', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'Authoritative name', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false,
  };
  let discovered = false;
  let scans = 0;
  const index = {
    resolveFast: async () => discovered ? row : undefined,
    scanFast: async () => { discovered = true; return { sessions: [row], needsRefresh: false }; },
    scan: async () => { scans++; return []; },
    readTranscript: () => [],
    extractSessionMetadata: () => ({}),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, () => {});
  try {
    assert.equal((await registry.openSession('listed')).name, 'Authoritative name');
    assert.equal(scans, 0);
  } finally {
    await registry.closeAll();
  }
});

test('opening a listed session resolves only that session, not the global scan', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'Authoritative name', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false,
  };
  let scans = 0;
  const index = {
    resolveFast: async (id: string) => id === row.id ? row : undefined,
    scan: async () => { scans++; return []; },
    readTranscript: () => [],
    extractSessionMetadata: () => ({}),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, () => {});
  try {
    const opened = await registry.openSession('listed');
    assert.equal(opened.name, 'Authoritative name');
    assert.equal(scans, 0);
  } finally {
    await registry.closeAll();
  }
});

test('a session opened with a provisional title receives the verified title', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'provisional', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false, isProvisional: true,
  };
  let revision = 0;
  let finish!: (rows: SessionSummary[]) => void;
  const event = waitForEvent();
  const index = {
    get cacheRevision() { return revision; },
    hasUnstableFiles: false,
    resolveFast: async () => row,
    scan: () => new Promise<SessionSummary[]>((resolve) => { finish = resolve; }),
    readTranscript: () => [],
    extractSessionMetadata: () => ({}),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => event.resolve(message));
  try {
    const opened = await registry.openSession('listed');
    assert.equal(opened.name, 'provisional');
    revision++;
    finish([{ ...row, name: 'verified', isProvisional: false }]);
    await event.promise;
    assert.equal(opened.name, 'verified');
  } finally {
    await registry.closeAll();
  }
});

test('provisional title is reconciled even when authoritative cache revision is unchanged', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'provisional', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false, isProvisional: true,
  };
  const event = waitForEvent();
  const index = {
    cacheRevision: 1,
    hasUnstableFiles: false,
    resolveFast: async () => row,
    scan: async () => [{ ...row, name: 'verified', isProvisional: false }],
    readTranscript: () => [],
    extractSessionMetadata: () => ({}),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => event.resolve(message));
  try {
    const opened = await registry.openSession('listed');
    await event.promise;
    assert.equal(opened.name, 'verified');
  } finally {
    await registry.closeAll();
  }
});

test('a provisional title queued as a refresh finishes is not stranded', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'provisional', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false, isProvisional: true,
  };
  const verified = { ...row, name: 'verified', isProvisional: false };
  let finishScan!: (rows: SessionSummary[]) => void;
  let finishOpen!: (row: SessionSummary) => void;
  let scans = 0;
  const event = waitForEvent();
  const index = {
    cacheRevision: 0,
    hasUnstableFiles: false,
    scanFast: async () => ({ sessions: [row], needsRefresh: true }),
    resolveFast: () => new Promise<SessionSummary>((resolve) => { finishOpen = resolve; }),
    scan: () => ++scans === 1
      ? new Promise<SessionSummary[]>((resolve) => { finishScan = resolve; })
      : Promise.resolve([verified]),
    readTranscript: () => [],
    extractSessionMetadata: () => ({}),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => event.resolve(message));
  try {
    await registry.listSessions();
    const opening = registry.openSession('listed');
    finishScan([verified]);
    queueMicrotask(() => finishOpen(row));
    const opened = await opening;
    await event.promise;
    assert.equal(opened.name, 'verified');
    assert.equal(scans, 2);
  } finally {
    await registry.closeAll();
  }
});

test('index refresh does not overwrite a manual rename made during loading', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'listed', name: 'provisional', cwd: process.cwd(), sessionFile: 'listed.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false, isProvisional: true,
  };
  let revision = 0;
  let finish!: (rows: SessionSummary[]) => void;
  const event = waitForEvent();
  const index = {
    get cacheRevision() { return revision; },
    hasUnstableFiles: false,
    resolveFast: async () => row,
    scan: () => new Promise<SessionSummary[]>((resolve) => { finish = resolve; }),
    readTranscript: () => [],
    extractSessionMetadata: () => ({}),
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => event.resolve(message));
  try {
    const opened = await registry.openSession('listed');
    opened.name = 'Manual rename';
    revision++;
    finish([{ ...row, name: 'verified', isProvisional: false }]);
    await event.promise;
    assert.equal(opened.name, 'Manual rename');
  } finally {
    await registry.closeAll();
  }
});

test('background indexing publishes progress before the full scan finishes', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'one', name: 'provisional', cwd: process.cwd(), sessionFile: 'one.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false,
  };
  let revision = 0;
  let report!: (revision: number) => void;
  let finish!: (rows: SessionSummary[]) => void;
  const progress = waitForEvent();
  const completed = waitForEvent();
  const index = {
    get cacheRevision() { return revision; },
    scanFast: async () => ({ sessions: [row], needsRefresh: true }),
    scan: (_active: Set<string>, onProgress: (revision: number) => void) => {
      report = onProgress;
      return new Promise<SessionSummary[]>((resolve) => { finish = resolve; });
    },
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => {
    if (message.payload.refreshing) progress.resolve(message);
    else completed.resolve(message);
  });
  try {
    await registry.listSessions();
    revision++;
    report(revision);
    assert.equal((await progress.promise).payload.refreshing, true);
    finish([{ ...row, name: 'exact' }]);
    assert.equal((await completed.promise).payload.updated[0].name, 'exact');
  } finally {
    await registry.closeAll();
  }
});

test('a session-list refresh queued during indexing runs after the in-flight snapshot', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'first', name: 'First', cwd: process.cwd(), sessionFile: 'first.jsonl',
    createdAt: 1, lastActivityAt: 2, sizeBytes: 1, isActive: false,
  };
  const added: SessionSummary = {
    ...row, id: 'second', name: 'Second', sessionFile: 'second.jsonl', lastActivityAt: 1,
  };
  let revision = 0;
  let scans = 0;
  let finishFirst!: (rows: SessionSummary[]) => void;
  let signalFirst!: () => void;
  const firstStarted = new Promise<void>((resolve) => { signalFirst = resolve; });
  const updated = waitForEvent();
  const index = {
    get cacheRevision() { return revision; },
    hasUnstableFiles: false,
    getCachedSnapshot: () => [row],
    scanFast: async () => ({ sessions: [row], needsRefresh: true }),
    scan: () => {
      scans++;
      if (scans === 1) {
        signalFirst();
        return new Promise<SessionSummary[]>((resolve) => { finishFirst = resolve; });
      }
      revision++;
      return Promise.resolve([row, added]);
    },
  } as unknown as SessionIndex;
  const registry = makeRegistry(index, (_sessionId, message) => {
    if (message.payload.updated?.some((item: SessionSummary) => item.id === added.id)) updated.resolve(message);
  });
  try {
    await registry.listSessions();
    await firstStarted;
    assert.deepEqual((await registry.listSessions()).map((item) => item.id), [row.id]);
    finishFirst([row]);
    const event = await updated.promise;
    assert.deepEqual(event.payload.updated.map((item: SessionSummary) => item.id), [row.id, added.id]);
    assert.equal(scans, 2);
  } finally {
    await registry.closeAll();
  }
});

test('concurrent list calls share one refresh and replay a queued follow-up', { timeout: 10_000 }, async () => {
  const row: SessionSummary = {
    id: 'one', name: 'provisional', cwd: process.cwd(), sessionFile: 'one.jsonl',
    createdAt: 1, lastActivityAt: 1, sizeBytes: 1, isActive: false,
  };
  const final = { ...row, name: 'exact', messageCount: 2 };
  let pending = true;
  let revision = 0;
  let scans = 0;
  let finish!: (rows: SessionSummary[]) => void;
  const event = waitForEvent();
  const index = {
    get cacheRevision() { return revision; },
    scanFast: async () => ({ sessions: [pending ? row : final], needsRefresh: pending }),
    scan: () => {
      scans++;
      return scans === 1
        ? new Promise<SessionSummary[]>((resolve) => { finish = resolve; })
        : Promise.resolve([final]);
    },
  } as unknown as SessionIndex;
  const events: any[] = [];
  const registry = makeRegistry(index, (_sessionId, message) => {
    events.push(message);
    event.resolve(message);
  });
  try {
    const [first, second] = await Promise.all([registry.listSessions(), registry.listSessions()]);
    assert.equal(first[0].name, 'provisional');
    assert.equal(second[0].name, 'provisional');
    assert.equal(scans, 1);
    pending = false;
    revision++;
    finish([final]);
    await event.promise;
    assert.equal((await registry.listSessions())[0].name, 'exact');
    assert.equal(scans, 2);
    assert.equal(events.length, 1);
    assert.equal(events[0].payload.updated[0].name, 'exact');
  } finally {
    await registry.closeAll();
  }
});

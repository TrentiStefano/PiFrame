/**
 * PiFrame's bridge to @tintinweb/pi-subagents, injected into every Pi worker
 * together with the context-limit extension.
 *
 * pi-subagents runs background agents inside the Pi process and keeps their
 * true state in its AgentManager. PiFrame used to guess that state from
 * session-file timestamps, which went wrong whenever an agent sat in a long
 * tool call (shown "completed" while /agents said "running") or died with its
 * worker (shown "running" forever). The bridge reports the manager's state to
 * the daemon instead, and stops agents through pi-subagents' own stop RPC.
 *
 * Self-contained: the function is emitted as source into the worker's
 * extension file, so it must not reference anything outside its own body.
 *
 * Channels, all documented by pi-subagents (docs/rpc.md):
 * - lifecycle events `subagents:created|started|completed|failed|steered` on
 *   `pi.events`, which give the ids of top-level agents;
 * - the manager registry `globalThis[Symbol.for("pi-subagents:manager")]`
 *   (`hasRunning()`, `getRecord(id)`) for their live status;
 * - `subagents:rpc:stop` to stop one, with the same ownership check `/agents`
 *   relies on.
 *
 * To the daemon it reports through `ctx.ui.setStatus(PIFRAME_SUBAGENTS_STATUS_KEY,
 * json)`, which arrives on this worker's own event stream; the daemon keeps it
 * as the session's live subagent state and never shows it as a status line.
 */
export function subagentBridgeExtension(pi: any): void {
  const STATUS_KEY = 'piframe-subagents';
  const MANAGER_KEY = Symbol.for('pi-subagents:manager');
  const OWNER_KEY = Symbol.for('piframe:subagent-bridge');
  const HEARTBEAT_MS = 3000;
  const STOP_TIMEOUT_MS = 5000;
  const g: any = globalThis as any;

  // pi-subagents re-activates extensions inside each subagent session of the
  // same process. Only the first activation (the root session) reports and
  // offers the stop tool; child activations stay silent.
  if (g[OWNER_KEY]) return;
  const ownerToken = {};
  g[OWNER_KEY] = ownerToken;

  const startedAt = Date.now();
  const known = new Map<string, any>();
  let ctxRef: any = null;
  let timer: any = null;
  let lastSent = '';
  let idleSince: number | null = startedAt;

  const registry = () => {
    const entry = g[MANAGER_KEY];
    return entry && typeof entry.getRecord === 'function' ? entry : null;
  };

  const remember = (data: any, status?: string) => {
    const id = data && typeof data.id === 'string' ? data.id : null;
    if (!id) return;
    const previous = known.get(id) ?? {};
    known.set(id, {
      ...previous,
      id,
      type: data.type ?? previous.type,
      description: data.description ?? previous.description,
      status: status ?? data.status ?? previous.status ?? 'running'
    });
  };

  const snapshot = () => {
    const manager = registry();
    let anyRunning = false;
    if (manager && typeof manager.hasRunning === 'function') {
      try {
        anyRunning = !!manager.hasRunning();
      } catch {
        anyRunning = false;
      }
    }
    const agents: any[] = [];
    for (const [id, info] of known) {
      let record: any;
      try {
        record = manager ? manager.getRecord(id) : undefined;
      } catch {
        record = undefined;
      }
      // A record leaves the manager about a minute after it settles; the last
      // status seen on the bus stands in for it then.
      agents.push({
        id,
        status: record?.status ?? info.status ?? 'running',
        type: record?.type ?? info.type,
        description: record?.description ?? info.description,
        startedAt: typeof record?.startedAt === 'number' ? record.startedAt : info.startedAt,
        completedAt: typeof record?.completedAt === 'number' ? record.completedAt : info.completedAt,
        toolUses: typeof record?.toolUses === 'number' ? record.toolUses : info.toolUses
      });
    }
    if (anyRunning) idleSince = null;
    else if (idleSince === null) idleSince = Date.now();
    return { v: 1, available: !!manager, anyRunning, idleSince, bridgeStartedAt: startedAt, agents };
  };

  const publish = () => {
    const ui = ctxRef?.ui;
    if (!ui || typeof ui.setStatus !== 'function') return;
    let json: string;
    try {
      json = JSON.stringify(snapshot());
    } catch {
      return;
    }
    if (json === lastSent) return;
    lastSent = json;
    try {
      ui.setStatus(STATUS_KEY, json);
    } catch {
      /* the worker is going away */
    }
  };

  const track = (ctx: any) => {
    if (ctx) ctxRef = ctx;
    publish();
  };

  const stopAgent = (agentId: string): Promise<{ ok: boolean; error?: string }> =>
    new Promise((resolve) => {
      const events = pi.events;
      if (!events || typeof events.on !== 'function' || typeof events.emit !== 'function') {
        resolve({ ok: false, error: 'pi-subagents is not available in this session.' });
        return;
      }
      const requestId = `piframe-stop-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      let settled = false;
      let unsubscribe: (() => void) | undefined;
      const finish = (result: { ok: boolean; error?: string }) => {
        if (settled) return;
        settled = true;
        try {
          unsubscribe?.();
        } catch {
          /* already gone */
        }
        publish();
        resolve(result);
      };
      unsubscribe = events.on(`subagents:rpc:stop:reply:${requestId}`, (reply: any) => {
        finish(reply?.success ? { ok: true } : { ok: false, error: String(reply?.error ?? 'Stop failed') });
      });
      setTimeout(() => finish({ ok: false, error: 'pi-subagents did not answer the stop request.' }), STOP_TIMEOUT_MS);
      events.emit('subagents:rpc:stop', { requestId, agentId });
    });

  if (pi.events && typeof pi.events.on === 'function') {
    pi.events.on('subagents:created', (data: any) => {
      remember(data);
      publish();
    });
    pi.events.on('subagents:started', (data: any) => {
      remember(data, 'running');
      const info = known.get(data?.id);
      if (info && info.startedAt === undefined) info.startedAt = Date.now();
      publish();
    });
    pi.events.on('subagents:steered', (data: any) => {
      remember(data);
      publish();
    });
    pi.events.on('subagents:completed', (data: any) => {
      remember(data, data?.status ?? 'completed');
      const info = known.get(data?.id);
      if (info) {
        info.completedAt = Date.now();
        info.toolUses = data?.toolUses ?? info.toolUses;
      }
      publish();
    });
    pi.events.on('subagents:failed', (data: any) => {
      remember(data, data?.status ?? 'error');
      const info = known.get(data?.id);
      if (info) {
        info.completedAt = Date.now();
        info.toolUses = data?.toolUses ?? info.toolUses;
      }
      publish();
    });
  }

  pi.registerCommand('piframe-subagent-stop', {
    description: 'PiFrame internal: stop a background subagent',
    handler: async (args: string, ctx: any) => {
      if (ctx) ctxRef = ctx;
      const agentId = String(args ?? '').trim();
      if (!agentId) throw new Error('Missing subagent id');
      const result = await stopAgent(agentId);
      if (!result.ok) throw new Error(result.error);
    }
  });

  // pi-subagents gives the main agent no way to stop a background agent, so a
  // stuck one could only be stopped by hand from /agents.
  if (typeof pi.registerTool === 'function') {
    pi.registerTool({
      name: 'stop_subagent',
      label: 'Stop Agent',
      description:
        'Stop a running background agent started with the Agent tool. Use it when the user asks to stop an agent, ' +
        'or when an agent is stuck or no longer needed. Pass the agent ID returned by Agent.',
      parameters: {
        type: 'object',
        properties: { agent_id: { type: 'string', description: 'The agent ID returned by Agent.' } },
        required: ['agent_id'],
        additionalProperties: false
      },
      execute: async (_toolCallId: string, params: any) => {
        const agentId = String(params?.agent_id ?? '').trim();
        const result = agentId ? await stopAgent(agentId) : { ok: false, error: 'Missing agent_id.' };
        const text = result.ok ? `Agent ${agentId} stopped.` : `Agent ${agentId} was not stopped: ${result.error}`;
        return { content: [{ type: 'text', text }], details: { agentId, stopped: result.ok } };
      }
    });
  }

  for (const event of ['session_start', 'before_agent_start', 'agent_settled', 'turn_end']) {
    pi.on(event, (_event: unknown, ctx: any) => {
      track(ctx);
    });
  }
  pi.on('session_start', (_event: unknown, ctx: any) => {
    ctxRef = ctx;
    if (!timer) {
      timer = setInterval(publish, HEARTBEAT_MS);
      if (typeof timer?.unref === 'function') timer.unref();
    }
    publish();
  });
  pi.on('session_shutdown', () => {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    if (g[OWNER_KEY] === ownerToken) delete g[OWNER_KEY];
  });
}

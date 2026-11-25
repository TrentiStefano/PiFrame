import { isRecord } from '../errors/errors.js';

/**
 * Live subagent state reported by PiFrame's bridge inside a Pi worker
 * (src/pi/subagentBridgeExtension.ts), and the rules that combine it with what
 * the session files say.
 *
 * pi-subagents runs background agents inside the worker process, so:
 * - while the bridge reports, its view is the truth for the agents it knows;
 * - an agent it does not know, in a worker where nothing runs, is not running;
 * - once PiFrame's worker for a session is gone, none of its agents can run.
 * Only a session PiFrame never ran in this daemon (it may be open in a Pi
 * terminal) still relies on the session-file heuristics.
 */

export const PIFRAME_SUBAGENTS_STATUS_KEY = 'piframe-subagents';

export interface LiveSubagent {
  id: string;
  status: string;
  type?: string;
  description?: string;
  startedAt?: number;
  completedAt?: number;
  toolUses?: number;
}

export interface LiveSubagentState {
  /** pi-subagents' manager registry exists in the worker. */
  available: boolean;
  /** Any agent at all is running, workflow agents included. */
  anyRunning: boolean;
  /** Since when nothing has been running; null while something runs. */
  idleSince: number | null;
  bridgeStartedAt: number;
  agents: LiveSubagent[];
  receivedAt: number;
}

/** What the daemon knows about the process the agents would run in. */
export interface SubagentRuntime {
  live: LiveSubagentState | null;
  workerAlive: boolean;
  /** PiFrame ran a worker for this session earlier and it has since gone. */
  workerGone: boolean;
}

const num = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isFinite(value) ? value : undefined;

/** Parses the bridge's status text; null when it is not a valid report. */
export function parseLiveSubagents(text: unknown, now = Date.now()): LiveSubagentState | null {
  if (typeof text !== 'string' || !text) return null;
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(raw) || raw.v !== 1 || !Array.isArray(raw.agents)) return null;
  const rawAgents: unknown[] = raw.agents;
  const agents: LiveSubagent[] = [];
  for (const agent of rawAgents) {
    if (!isRecord(agent) || typeof agent.id !== 'string' || !agent.id) continue;
    agents.push({
      id: agent.id,
      status: typeof agent.status === 'string' ? agent.status : 'running',
      type: typeof agent.type === 'string' ? agent.type : undefined,
      description: typeof agent.description === 'string' ? agent.description : undefined,
      startedAt: num(agent.startedAt),
      completedAt: num(agent.completedAt),
      toolUses: num(agent.toolUses)
    });
  }
  return {
    available: raw.available === true,
    anyRunning: raw.anyRunning === true,
    idleSince: num(raw.idleSince) ?? null,
    bridgeStartedAt: num(raw.bridgeStartedAt) ?? now,
    agents,
    receivedAt: now
  };
}

/** pi-subagents' record status in PiFrame's vocabulary. */
export function mapLiveStatus(status: string): string {
  switch (status) {
    case 'queued':
    case 'running':
      return 'running';
    case 'completed':
      return 'completed';
    case 'steered':
      return 'steered';
    case 'stopped':
    case 'aborted':
      return 'stopped';
    case 'error':
      return 'error';
    default:
      return 'running';
  }
}

/**
 * The status to show for one agent. [item.status] is what the session files
 * say; [item.finished] whether its child session wrote a final answer.
 */
export function resolveSubagentStatus(
  item: { id: string; status: string; unlinked?: boolean; finished?: boolean },
  runtime: SubagentRuntime
): string {
  const ended = item.finished ? 'completed' : 'stopped';
  const live = runtime.live;
  if (runtime.workerAlive && live?.available) {
    const record = live.agents.find((agent) => agent.id === item.id);
    if (record) return mapLiveStatus(record.status);
    if (item.status !== 'running') return item.status;
    // Nothing runs in this worker, so this agent does not either.
    if (!live.anyRunning) return ended;
    // A workflow's agents are owned by the workflow and never listed: while
    // something runs, the session files still decide for them.
    if (item.unlinked) return item.status;
    // A top-level agent this worker never started: launched by an earlier
    // process that is gone.
    return ended;
  }
  // The worker these agents ran in has stopped or crashed.
  if (!runtime.workerAlive && runtime.workerGone && item.status === 'running') return ended;
  return item.status;
}

/**
 * Waits until the bridge reports [agentId] no longer running (or nothing
 * running at all once it has left the registry). True when confirmed.
 */
export async function awaitSubagentStopped(
  read: () => LiveSubagentState | null,
  agentId: string,
  timeoutMs: number,
  pollMs = 150
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const live = read();
    const record = live?.agents.find((agent) => agent.id === agentId);
    if (record && mapLiveStatus(record.status) !== 'running') return true;
    if (live && !record && live.anyRunning === false) return true;
    if (Date.now() >= deadline) return false;
    await new Promise((resolve) => setTimeout(resolve, pollMs));
  }
}

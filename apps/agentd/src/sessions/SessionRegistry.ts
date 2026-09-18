import { ulid } from 'ulid';
import { Session } from './Session.js';
import { SessionIndex, type SessionSummary } from './SessionIndex.js';
import { WorkerSupervisor } from './WorkerSupervisor.js';
import type { ConnectionManager } from '../server/wsServer.js';
import type { Connection } from '../server/connection.js';
import type { PiCapabilities } from '../pi/piCommands.js';
import type { PcpSnapshot, PcpSnapshotPayload } from '@pi-crust/pcp-ts';

export interface SessionRegistryOptions {
  piExecutablePath: string;
  capabilities: PiCapabilities;
  workerIdleTimeoutMs: number;
  connectionManager: ConnectionManager;
}

export class SessionRegistry {
  private sessions = new Map<string, Session>();
  private index: SessionIndex;
  private supervisor: WorkerSupervisor;
  private connectionManager: ConnectionManager;

  constructor(opts: SessionRegistryOptions) {
    this.index = new SessionIndex();
    this.connectionManager = opts.connectionManager;
    this.supervisor = new WorkerSupervisor({
      piExecutablePath: opts.piExecutablePath,
      capabilities: opts.capabilities,
      defaultIdleTimeoutMs: opts.workerIdleTimeoutMs
    });
  }

  public getSupervisor(): WorkerSupervisor {
    return this.supervisor;
  }

  public getSession(id: string): Session | undefined {
    return this.sessions.get(id);
  }

  public async listSessions(): Promise<SessionSummary[]> {
    const activeIds = new Set(this.sessions.keys());
    return this.index.scan(activeIds);
  }

  public async createSession(opts: { cwd?: string; name?: string }): Promise<Session> {
    const id = `s_${ulid()}`;
    const cwd = opts.cwd || process.cwd();
    const name = opts.name || `Session ${new Date().toLocaleTimeString()}`;

    const session = new Session({
      id,
      name,
      cwd,
      onBroadcast: (event) => {
        this.connectionManager.broadcast(id, event);
      }
    });

    this.sessions.set(id, session);

    // Broadcast index change on @daemon
    this.connectionManager.broadcast('@daemon', {
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: '@daemon',
      seq: 0,
      type: 'session.indexChanged',
      payload: {
        added: [session.getSessionMeta()]
      }
    } as any);

    return session;
  }

  public async openSession(id: string, cwd?: string): Promise<Session> {
    const existing = this.sessions.get(id);
    if (existing) {
      return existing;
    }

    // Try finding in session index
    const summaries = await this.index.scan();
    const found = summaries.find((s) => s.id === id);

    const session = new Session({
      id,
      name: found?.name || id,
      cwd: cwd || found?.cwd || process.cwd(),
      sessionFile: found?.sessionFile,
      createdAt: found?.createdAt,
      onBroadcast: (event) => {
        this.connectionManager.broadcast(id, event);
      }
    });

    this.sessions.set(id, session);
    return session;
  }

  public async attachClient(sessionId: string, conn: Connection, lastSeq: number | null): Promise<void> {
    let session = this.sessions.get(sessionId);
    if (!session) {
      session = await this.openSession(sessionId);
    }

    session.attachedClientIds.add(conn.id);
    conn.attachedSessions.add(sessionId);

    const currentSeq = session.journal.currentSeq;
    const minSeq = session.journal.minSeq;

    // Check if replay is possible or snapshot is needed
    if (lastSeq !== null && lastSeq >= minSeq && lastSeq <= currentSeq) {
      // Replay missing events from journal
      const events = session.journal.getRange(lastSeq + 1, currentSeq);
      for (const event of events) {
        conn.send(event);
      }
    } else {
      // Send full snapshot
      const snapshotPayload: PcpSnapshotPayload = session.getSnapshot();
      const snapshotMessage: PcpSnapshot = {
        protocol: 1,
        kind: 'snapshot',
        id: `snp_${ulid()}`,
        ts: Date.now(),
        sessionId,
        seq: session.journal.currentSeq,
        type: 'session.snapshot',
        payload: snapshotPayload
      };
      conn.send(snapshotMessage);
    }
  }

  public async detachClient(sessionId: string, conn: Connection): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.attachedClientIds.delete(conn.id);
      conn.attachedSessions.delete(sessionId);
    }
  }

  public async ensureWorkerForSession(sessionId: string) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }
    return this.supervisor.ensureWorker(session);
  }

  public async closeWorker(sessionId: string): Promise<void> {
    await this.supervisor.stopWorker(sessionId);
  }

  public async closeAll(graceMs = 5000): Promise<void> {
    await this.supervisor.stopAll(graceMs);
    for (const session of this.sessions.values()) {
      session.close();
    }
  }
}

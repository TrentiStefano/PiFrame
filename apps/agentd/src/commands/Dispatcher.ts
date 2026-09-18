import { ulid } from 'ulid';
import type { Connection } from '../server/connection.js';
import type { SessionRegistry } from '../sessions/SessionRegistry.js';
import type { ConnectionManager } from '../server/wsServer.js';
import { CommandDeduplicator } from './CommandRecord.js';
import { loadConfig, patchConfig, type DaemonConfig } from '../config/config.js';
import type {
  PcpCommand,
  PcpAck,
  PcpResult,
  PcpError,
  PcpResultPayload
} from '@pi-crust/pcp-ts';

export class Dispatcher {
  private registry: SessionRegistry;
  private connectionManager: ConnectionManager;
  private deduplicator = new CommandDeduplicator();

  constructor(registry: SessionRegistry, connectionManager: ConnectionManager) {
    this.registry = registry;
    this.connectionManager = connectionManager;
  }

  public async handle(conn: Connection, cmd: PcpCommand): Promise<void> {
    const commandId = cmd.commandId;
    const type = cmd.type;
    const now = Date.now();

    // 1. Check idempotency / deduplication
    const existing = this.deduplicator.get(commandId);
    if (existing) {
      if (existing.state === 'executing') {
        // Still in-flight: send ACK and wait for the original completion
        this.sendAck(conn, commandId);
        existing.waiters.push((payload) => {
          this.sendResult(conn, commandId, payload.state === 'completed' ? 'deduplicated' : payload.state, payload.data, payload.error);
        });
        return;
      }

      // Already finished: immediately replay stored result
      this.sendAck(conn, commandId);
      this.sendResult(
        conn,
        commandId,
        existing.state === 'completed' ? 'deduplicated' : (existing.state as any),
        existing.resultPayload?.data,
        existing.resultPayload?.error
      );
      return;
    }

    // Register new command record
    this.deduplicator.register(commandId, type);

    // 2. Immediate ACK
    this.sendAck(conn, commandId);

    // 3. Execute command
    try {
      const data = await this.execute(conn, cmd);
      const payload = this.deduplicator.complete(commandId, 'completed', data);
      this.sendResult(conn, commandId, 'completed', payload.data);
    } catch (err: any) {
      const isRejected = err.code === 'COMMAND_REJECTED' || err.code === 'CONFIG_INVALID' || err.code === 'SESSION_NOT_FOUND';
      const state = isRejected ? 'rejected' : 'failed';
      const payload = this.deduplicator.complete(commandId, state, undefined, err.message);
      this.sendResult(conn, commandId, state, undefined, payload.error);

      // Also send detailed PcpError envelope
      conn.send({
        protocol: 1,
        kind: 'error',
        id: `err_${ulid()}`,
        ts: Date.now(),
        commandId,
        type: 'error',
        payload: {
          code: err.code || (isRejected ? 'COMMAND_REJECTED' : 'INTERNAL'),
          message: err.message,
          hint: err.hint,
          details: err.details
        }
      } as PcpError);
    }
  }

  private sendAck(conn: Connection, commandId: string): void {
    conn.send({
      protocol: 1,
      kind: 'ack',
      id: `ack_${ulid()}`,
      ts: Date.now(),
      commandId,
      type: 'command.ack',
      payload: { state: 'accepted' }
    } as PcpAck);
  }

  private sendResult(conn: Connection, commandId: string, state: any, data?: any, error?: string): void {
    conn.send({
      protocol: 1,
      kind: 'result',
      id: `res_${ulid()}`,
      ts: Date.now(),
      commandId,
      type: 'command.result',
      payload: { state, data, error }
    } as PcpResult);
  }

  private async execute(conn: Connection, cmd: PcpCommand): Promise<any> {
    const payload = (cmd.payload || {}) as Record<string, any>;
    const sessionId = cmd.sessionId;

    switch (cmd.type) {
      // -----------------------------------------------------------------------
      // Daemon configuration
      // -----------------------------------------------------------------------
      case 'daemon.getConfig': {
        return loadConfig();
      }

      case 'daemon.setConfig': {
        const patch = payload;
        if (patch.workerIdleTimeoutMs !== undefined) {
          const ms = Number(patch.workerIdleTimeoutMs);
          if (isNaN(ms) || ms < 0 || ms > 86400000) {
            const err: any = new Error('workerIdleTimeoutMs must be between 0 and 86400000 ms');
            err.code = 'CONFIG_INVALID';
            throw err;
          }
        }
        const updated = patchConfig(patch);
        this.registry.getSupervisor().updateIdleTimeout(updated.workerIdleTimeoutMs);

        // Broadcast to ALL connected clients
        this.connectionManager.broadcastAll({
          protocol: 1,
          kind: 'event',
          id: `evt_${ulid()}`,
          ts: Date.now(),
          sessionId: '@daemon',
          seq: 0,
          type: 'daemon.configChanged',
          payload: { config: updated }
        } as any);

        return updated;
      }

      // -----------------------------------------------------------------------
      // Session Management
      // -----------------------------------------------------------------------
      case 'session.list': {
        return { sessions: await this.registry.listSessions() };
      }

      case 'session.create': {
        const session = await this.registry.createSession({
          cwd: payload.cwd,
          name: payload.name
        });
        return { session: session.getSessionMeta() };
      }

      case 'session.open': {
        if (!sessionId) throw new Error('sessionId is required for session.open');
        const session = await this.registry.openSession(sessionId, payload.cwd);
        if (session.status === 'worker_error' || !session.worker || !session.worker.health().alive) {
          await this.registry.getSupervisor().reconcileAndRespawn(session);
        }
        return { session: session.getSessionMeta() };
      }

      case 'session.attach': {
        return { attached: true, sessionId };
      }

      case 'session.detach': {
        return { detached: true, sessionId };
      }

      case 'session.getStats': {
        if (!sessionId) throw new Error('sessionId required for session.getStats');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'get_session_stats' });
        return res.data;
      }

      case 'session.getEntries': {
        if (!sessionId) throw new Error('sessionId required for session.getEntries');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'get_entries',
          arguments: payload.since ? { since: payload.since } : {}
        });
        return res.data;
      }

      case 'session.closeWorker': {
        if (!sessionId) throw new Error('sessionId is required for session.closeWorker');
        await this.registry.closeWorker(sessionId);
        return { closed: true };
      }

      // -----------------------------------------------------------------------
      // Agent Commands
      // -----------------------------------------------------------------------
      case 'agent.prompt': {
        if (!sessionId) throw new Error('sessionId required for agent.prompt');
        const session = this.registry.getSession(sessionId);
        if (!session) {
          const err: any = new Error(`Session ${sessionId} not found`);
          err.code = 'SESSION_NOT_FOUND';
          throw err;
        }

        // §2.8 Rule: If streaming is active, require explicit streamingBehavior
        if (session.isStreaming && !payload.streamingBehavior) {
          const err: any = new Error('Agent is streaming. Specify streamingBehavior ("steer" or "followUp").');
          err.code = 'COMMAND_REJECTED';
          err.hint = 'Usa Steer o Follow-up durante lo streaming.';
          throw err;
        }

        const worker = await this.registry.ensureWorkerForSession(sessionId);

        if (payload.streamingBehavior === 'steer') {
          const res = await worker.send({
            command: 'steer',
            arguments: { message: payload.text, images: payload.images }
          });
          return res.data;
        } else if (payload.streamingBehavior === 'followUp') {
          const res = await worker.send({
            command: 'follow_up',
            arguments: { message: payload.text, images: payload.images }
          });
          return res.data;
        } else {
          const res = await worker.send({
            command: 'prompt',
            arguments: { message: payload.text, images: payload.images }
          });
          return res.data;
        }
      }

      case 'agent.steer': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'steer',
          arguments: { message: payload.text }
        });
        return res.data;
      }

      case 'agent.followUp': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'follow_up',
          arguments: { message: payload.text }
        });
        return res.data;
      }

      case 'agent.clearQueue': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'clear_queue' });
        return res.data;
      }

      case 'agent.interrupt': {
        // Esc semantics:
        // 1. clear_queue -> captures { steering, followUp }
        // 2. abort -> halts active stream
        // 3. returns saved text for client composer restoration!
        if (!sessionId) throw new Error('sessionId required');
        const session = this.registry.getSession(sessionId);
        let restoredQueue = { steering: [] as string[], followUp: [] as string[] };

        if (session && session.worker) {
          try {
            const clearRes = await session.worker.send({ command: 'clear_queue' });
            if (clearRes.data) {
              restoredQueue = {
                steering: clearRes.data.steering || [],
                followUp: clearRes.data.followUp || []
              };
            }
          } catch {}

          try {
            await session.worker.send({ command: 'abort' });
          } catch {}
        }

        return { interrupted: true, queue: restoredQueue };
      }

      case 'agent.abort': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'abort' });
        return res.data;
      }

      case 'agent.compact': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'compact' });
        return res.data;
      }

      case 'agent.setAutoCompaction': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_auto_compaction',
          arguments: { enabled: payload.enabled }
        });
        const session = this.registry.getSession(sessionId);
        if (session) session.autoCompaction = !!payload.enabled;
        return res.data;
      }

      case 'agent.setAutoRetry': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_auto_retry',
          arguments: { enabled: payload.enabled }
        });
        return res.data;
      }

      case 'agent.setSteeringMode': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_steering_mode',
          arguments: { mode: payload.mode }
        });
        const session = this.registry.getSession(sessionId);
        if (session) session.steeringMode = payload.mode;
        return res.data;
      }

      case 'agent.setFollowUpMode': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_follow_up_mode',
          arguments: { mode: payload.mode }
        });
        const session = this.registry.getSession(sessionId);
        if (session) session.followUpMode = payload.mode;
        return res.data;
      }

      case 'agent.setModel': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_model',
          arguments: { provider: payload.provider, modelId: payload.modelId }
        });
        return res.data;
      }

      case 'agent.getModels': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'get_available_models' });
        return res.data;
      }

      case 'agent.setThinkingLevel': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_thinking_level',
          arguments: { level: payload.level }
        });
        return res.data;
      }

      case 'agent.getThinkingLevels': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'get_available_thinking_levels' });
        return res.data;
      }

      case 'agent.getCommands': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'get_commands' });
        return res.data;
      }

      case 'ui.claim': {
        if (!sessionId) throw new Error('sessionId required for ui.claim');
        const session = this.registry.getSession(sessionId);
        if (!session) {
          const err: any = new Error(`Session ${sessionId} not found`);
          err.code = 'SESSION_NOT_FOUND';
          throw err;
        }
        const claimRes = session.uiBroker.claimRequest(payload.requestId, conn.id);
        if (!claimRes.success) {
          const err: any = new Error(claimRes.reason || 'Failed to claim UI request');
          err.code = 'UI_REQUEST_NOT_CLAIMED';
          throw err;
        }
        return { claimed: true, requestId: payload.requestId };
      }

      case 'ui.respond': {
        if (!sessionId) throw new Error('sessionId required');
        const session = this.registry.getSession(sessionId);
        if (!session) {
          const err: any = new Error(`Session ${sessionId} not found`);
          err.code = 'SESSION_NOT_FOUND';
          throw err;
        }

        const resolveRes = session.uiBroker.resolveRequest(
          payload.requestId,
          conn.id,
          payload.cancelled ? 'cancelled' : payload.confirmed ? 'confirmed' : 'value'
        );
        if (!resolveRes.success) {
          const err: any = new Error(resolveRes.reason || 'Failed to resolve UI request');
          err.code = 'UI_REQUEST_NOT_CLAIMED';
          throw err;
        }

        if (session.worker) {
          const res = await session.worker.send({
            command: 'extension_ui_response',
            arguments: {
              id: payload.requestId,
              value: payload.value,
              confirmed: payload.confirmed,
              cancelled: payload.cancelled
            }
          });
          return res.data;
        }
        return { ok: true };
      }

      default: {
        const err: any = new Error(`Unsupported command type: ${cmd.type}`);
        err.code = 'COMMAND_REJECTED';
        throw err;
      }
    }
  }
}

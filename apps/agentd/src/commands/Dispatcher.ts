import * as fs from 'node:fs';
import * as path from 'node:path';
import { ulid } from 'ulid';
import type { Connection } from '../server/connection.js';
import type { SessionRegistry } from '../sessions/SessionRegistry.js';
import type { ConnectionManager } from '../server/wsServer.js';
import { CommandDeduplicator } from './CommandRecord.js';
import { loadConfig, patchConfig } from '../config/config.js';
import { WorkspaceService } from '../workspace/WorkspaceService.js';
import { SessionIndex } from '../sessions/SessionIndex.js';
import { filterModelsByEnabledPatterns, readEnabledModelPatterns } from '../pi/modelScope.js';
import { PiPackageService, type PiPackageOperations } from '../pi/PiPackageService.js';
import type { RemoteManager } from '../remote/RemoteManager.js';
import type {
  PcpCommand,
  PcpAck,
  PcpResult,
  PcpError
} from '@piframe/pcp-ts';

export class Dispatcher {
  private registry: SessionRegistry;
  private connectionManager: ConnectionManager;
  private deduplicator = new CommandDeduplicator();
  private workspaceService = new WorkspaceService();
  private sessionIndex: SessionIndex;
  private piPackages: PiPackageOperations;
  private remoteManager?: RemoteManager;

  constructor(
    registry: SessionRegistry,
    connectionManager: ConnectionManager,
    piPackages?: PiPackageOperations,
    remoteManager?: RemoteManager
  ) {
    this.registry = registry;
    this.connectionManager = connectionManager;
    this.sessionIndex = registry.getIndex();
    this.piPackages = piPackages ?? new PiPackageService(registry.getPiExecutablePath());
    this.remoteManager = remoteManager;

    if (this.remoteManager) {
      this.remoteManager.on('statusChanged', (status) => {
        // Broadcast ONLY to local connections (H2/H4: never leak pairing secrets or client IPs to remote devices)
        this.connectionManager.broadcastLocal('@daemon', {
          protocol: 1,
          kind: 'event',
          id: `ev_${ulid()}`,
          ts: Date.now(),
          sessionId: '@daemon',
          seq: 0,
          type: 'remote.statusChanged',
          payload: status
        } as any);
      });
    }
  }

  public async handle(conn: Connection, cmd: PcpCommand): Promise<void> {
    const commandId = cmd.commandId;
    const type = cmd.type;

    // 1. Check idempotency / deduplication
    const existing = this.deduplicator.get(commandId);
    if (existing) {
      if (existing.state === 'executing') {
        this.sendAck(conn, commandId);
        existing.waiters.push((payload) => {
          this.sendResult(conn, commandId, payload.state === 'completed' ? 'deduplicated' : payload.state, payload.data, payload.error);
        });
        return;
      }

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
      const isRejected =
        err.code === 'COMMAND_REJECTED' ||
        err.code === 'CONFIG_INVALID' ||
        err.code === 'SESSION_NOT_FOUND' ||
        String(err.code || '').startsWith('WORKSPACE_') ||
        String(err.code || '').startsWith('REMOTE_');
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

  private async requireWorkspaceSession(sessionId?: string): Promise<NonNullable<ReturnType<SessionRegistry['getSession']>>> {
    if (!sessionId) throw Object.assign(new Error('sessionId is required for workspace commands.'), { code: 'SESSION_NOT_FOUND' });
    let session = this.registry.getSession(sessionId);
    if (!session) {
      try {
        session = await this.registry.openSession(sessionId);
      } catch (_) {}
    }
    if (!session) throw Object.assign(new Error(`Session ${sessionId} not found.`), { code: 'SESSION_NOT_FOUND' });
    return session;
  }

  private assertWorkspaceWritable(session: NonNullable<ReturnType<SessionRegistry['getSession']>>): void {
    if (session.readOnly) {
      throw Object.assign(new Error('Repository writes are disabled for read-only sessions.'), { code: 'COMMAND_REJECTED' });
    }
    const activeTool = Array.from(session.activeTools.values()).some((tool: any) => tool.isRunning);
    if (activeTool || session.isStreaming || session.isCompacting || ['working', 'retrying', 'compacting', 'awaiting_user'].includes(session.status)) {
      throw Object.assign(new Error('Repository writes are disabled while the Pi worker is active.'), { code: 'COMMAND_REJECTED' });
    }
  }

  private async validateSessionCwd(candidateCwd?: unknown): Promise<string> {
    const raw = typeof candidateCwd === 'string' ? candidateCwd.trim() : '';
    if (!raw) {
      return process.env.INIT_CWD || process.cwd();
    }
    const resolved = path.resolve(raw);
    if (!fs.existsSync(resolved)) {
      throw Object.assign(new Error(`Directory '${raw}' does not exist`), {
        code: 'WORKSPACE_NOT_FOUND'
      });
    }
    const stat = fs.statSync(resolved);
    if (!stat.isDirectory()) {
      throw Object.assign(new Error(`Path '${raw}' is not a directory`), {
        code: 'WORKSPACE_INVALID'
      });
    }
    return resolved;
  }

  private async execute(conn: Connection, cmd: PcpCommand): Promise<any> {
    const payload = (cmd.payload || {}) as Record<string, any>;
    const sessionId = cmd.sessionId;

    // -------------------------------------------------------------------------
    // STRICT DEFAULT-DENY ALLOWLIST FOR REMOTE CONNECTIONS (C1, C2)
    // -------------------------------------------------------------------------
    if (conn.isRemote) {
      // 1. Verify that the device credential is still active in the database
      let dev = this.remoteManager?.getAuthManager().getDevice(conn.deviceId);
      if (!dev) {
        conn.close(4003, 'Device Revoked');
        throw Object.assign(new Error('Remote device is not registered or has expired'), {
          code: 'REMOTE_FORBIDDEN'
        });
      }

      const mode = dev.mode; // 'view' | 'control'

      // Commands permitted in 'view' mode (observability and non-mutating inspection, plus abort/interrupt)
      const VIEW_ALLOWED = new Set([
        'session.list',
        'session.attach',
        'session.detach',
        'session.getStats',
        'session.getEntries',
        'session.getTree',
        'session.subagents',
        'agent.getModels',
        'agent.getThinkingLevels',
        'agent.getCommands',
        'agent.abort',
        'agent.interrupt',
        'workspace.refresh',
        'workspace.getDiff',
        'workspace.listFiles',
        'workspace.readFile'
      ]);

      // Additional commands permitted ONLY in 'control' mode
      const CONTROL_EXTRA = new Set([
        'agent.prompt',
        'agent.steer',
        'agent.followUp',
        'agent.clearQueue',
        'agent.compact',
        'agent.setAutoCompaction',
        'agent.setAutoRetry',
        'agent.setSteeringMode',
        'agent.setFollowUpMode',
        'agent.setModel',
        'agent.setThinkingLevel',
        'ui.claim',
        'ui.respond',
        'session.create',
        'session.rename',
        'session.fork',
        'session.clone',
        'session.closeWorker',
        'workspace.saveFile',
        'workspace.gitAction'
      ]);

      if (cmd.type === 'session.open') {
        // session.open without continue is allowed in 'view'; with continue requires 'control'
        if (mode === 'view' && payload.continue === true) {
          throw Object.assign(new Error('Action blocked: continuing a session requires control mode permission.'), {
            code: 'REMOTE_FORBIDDEN'
          });
        }
      } else if (VIEW_ALLOWED.has(cmd.type)) {
        // Allowed in both view and control modes
      } else if (mode === 'control' && CONTROL_EXTRA.has(cmd.type)) {
        // Allowed in control mode
      } else {
        throw Object.assign(
          new Error(`Action blocked: command '${cmd.type}' is not permitted for remote connections in '${mode}' mode.`),
          { code: 'REMOTE_FORBIDDEN' }
        );
      }
    }

    switch (cmd.type) {
      // -----------------------------------------------------------------------
      // Remote Access Management (LOCAL ONLY)
      // -----------------------------------------------------------------------
      case 'remote.getStatus': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.getStatus is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          return { enabled: false, state: 'stopped', devices: [], options: { defaultMode: 'view' } };
        }
        return this.remoteManager.getStatus();
      }

      case 'remote.start': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.start is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        return await this.remoteManager.start(payload as any);
      }

      case 'remote.installCloudflared': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.installCloudflared is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        return await this.remoteManager.installCloudflared();
      }

      case 'remote.installTailscale': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.installTailscale is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        return await this.remoteManager.installTailscale();
      }

      case 'remote.setTailscaleHostname': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.setTailscaleHostname is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        const hostname = String(payload.hostname || '');
        return this.remoteManager.setTailscaleHostname(hostname);
      }

      case 'remote.stop': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.stop is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        return await this.remoteManager.stop();
      }

      case 'remote.generatePairing': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.generatePairing is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        return this.remoteManager.generatePairing(payload.ttlMs);
      }

      case 'remote.setDeviceMode': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.setDeviceMode is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        const deviceId = String(payload.deviceId || '');
        const mode = payload.mode;
        if (!deviceId) throw Object.assign(new Error('Missing deviceId'), { code: 'COMMAND_REJECTED' });
        if (mode !== 'view' && mode !== 'control') {
          throw Object.assign(new Error('Invalid mode: must be view or control'), { code: 'COMMAND_REJECTED' });
        }
        const ok = this.remoteManager.setDeviceMode(deviceId, mode);
        return { ok, deviceId, mode };
      }

      case 'remote.revokeDevice': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.revokeDevice is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        const deviceId = String(payload.deviceId || '');
        if (!deviceId) throw Object.assign(new Error('Missing deviceId'), { code: 'COMMAND_REJECTED' });
        const ok = this.remoteManager.revokeDevice(deviceId);
        return { ok, deviceId };
      }

      case 'remote.revokeAll': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.revokeAll is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        this.remoteManager.revokeAll();
        return { ok: true };
      }

      case 'remote.setOptions': {
        if (conn.isRemote) {
          throw Object.assign(new Error('remote.setOptions is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        if (!this.remoteManager) {
          throw Object.assign(new Error('Remote manager is not initialized'), { code: 'COMMAND_REJECTED' });
        }
        return this.remoteManager.setOptions(payload as any);
      }

      // -----------------------------------------------------------------------
      // Pi Packages Management (LOCAL ONLY)
      // -----------------------------------------------------------------------
      case 'pi.packages.list':
        if (conn.isRemote) {
          throw Object.assign(new Error('pi.packages is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        return { packages: await this.piPackages.list() };

      case 'pi.packages.update':
        if (conn.isRemote) {
          throw Object.assign(new Error('pi.packages is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        return await this.piPackages.update(String(payload.source ?? ''));

      case 'pi.packages.remove':
        if (conn.isRemote) {
          throw Object.assign(new Error('pi.packages is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        return await this.piPackages.remove(String(payload.source ?? ''));

      case 'pi.packages.pin':
        if (conn.isRemote) {
          throw Object.assign(new Error('pi.packages is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        return await this.piPackages.pin(
          String(payload.source ?? ''),
          String(payload.version ?? '')
        );

      // -----------------------------------------------------------------------
      // Daemon configuration (LOCAL ONLY)
      // -----------------------------------------------------------------------
      case 'daemon.getConfig': {
        if (conn.isRemote) {
          throw Object.assign(new Error('daemon.getConfig is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        return loadConfig();
      }

      case 'daemon.setConfig': {
        if (conn.isRemote) {
          throw Object.assign(new Error('daemon.setConfig is only available locally'), { code: 'REMOTE_FORBIDDEN' });
        }
        const patch = payload;
        // Strictly prohibit modifying remote or web sections through generic daemon.setConfig
        if ('remote' in patch || 'web' in patch) {
          throw Object.assign(
            new Error('daemon.setConfig cannot modify "remote" or "web" sections. Use remote.* commands.'),
            { code: 'CONFIG_INVALID' }
          );
        }

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

        // Broadcast to LOCAL connections ONLY
        this.connectionManager.broadcastLocal('@daemon', {
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
        const sessions = await this.registry.listSessions(
          payload?.query,
          payload?.limit,
          payload?.includeSubsessions === true
        );
        return { sessions };
      }

      case 'session.subagents': {
        if (!sessionId) throw new Error('sessionId is required for session.subagents');
        const subagents = await this.registry.getSubagents(sessionId);
        return { subagents };
      }

      case 'session.create': {
        const cwd = await this.validateSessionCwd(payload.cwd);
        const session = await this.registry.createSession({
          cwd,
          name: payload.name
        });
        return { session: session.getSessionMeta() };
      }

      case 'session.open': {
        if (!sessionId) throw new Error('sessionId is required for session.open');
        const cwd = payload.cwd ? await this.validateSessionCwd(payload.cwd) : undefined;
        const session = payload.continue === true
          ? await this.registry.continueSession(sessionId, payload.confirmed === true)
          : await this.registry.openSession(sessionId, cwd);
        if (!session.readOnly && (session.status === 'worker_error' || !session.worker || !session.worker.health().alive)) {
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

      case 'session.delete': {
        if (!sessionId) throw new Error('sessionId is required for session.delete');
        await this.registry.deleteSession(sessionId);
        return { deleted: true, sessionId };
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
        const session = this.registry.getSession(sessionId);
        if (session) session.model = res.data;
        return res.data;
      }

      case 'agent.getModels': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({ command: 'get_available_models' });
        const models = Array.isArray(res.data?.models) ? res.data.models : [];
        const session = this.registry.getSession(sessionId);
        return {
          ...res.data,
          currentModel: session?.model,
          currentThinkingLevel: session?.thinkingLevel,
          models: filterModelsByEnabledPatterns(models, readEnabledModelPatterns())
        };
      }

      case 'agent.setThinkingLevel': {
        if (!sessionId) throw new Error('sessionId required');
        const worker = await this.registry.ensureWorkerForSession(sessionId);
        const res = await worker.send({
          command: 'set_thinking_level',
          arguments: { level: payload.level }
        });
        const session = this.registry.getSession(sessionId);
        if (session) session.thinkingLevel = payload.level;
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

      case 'workspace.refresh': {
        const session = await this.requireWorkspaceSession(sessionId);
        return this.workspaceService.getStatus(session.cwd, true);
      }

      case 'workspace.getDiff': {
        const session = await this.requireWorkspaceSession(sessionId);
        const diff = await this.workspaceService.getDiff(session.cwd, payload?.filePath);
        return { diff };
      }

      case 'workspace.listFiles': {
        const session = await this.requireWorkspaceSession(sessionId);
        return this.workspaceService.listFiles(session.cwd);
      }

      case 'workspace.readFile': {
        const session = await this.requireWorkspaceSession(sessionId);
        return this.workspaceService.readFile(session.cwd, payload.path);
      }

      case 'workspace.saveFile': {
        const session = await this.requireWorkspaceSession(sessionId);
        const assertCanWrite = () => this.assertWorkspaceWritable(session);
        return this.workspaceService.saveFile(session.cwd, payload.path, payload.content, payload.revision, assertCanWrite);
      }

      case 'workspace.gitAction': {
        const session = await this.requireWorkspaceSession(sessionId);
        const assertCanWrite = () => this.assertWorkspaceWritable(session);
        return this.workspaceService.gitAction(
          session.cwd,
          payload.action,
          payload.paths,
          payload.expectedStagedPaths,
          payload.message,
          assertCanWrite
        );
      }

      case 'session.rename': {
        if (!sessionId) throw new Error('sessionId required');
        let session = this.registry.getSession(sessionId);
        if (!session) {
          try { session = await this.registry.openSession(sessionId); } catch (_) {}
        }
        if (!session) throw new Error(`Session ${sessionId} not found`);
        if (session.readOnly) throw new Error('External session is read-only. Duplicate it first.');
        session.name = payload.name;
        if (session.worker) {
          try {
            await session.worker.send({ command: 'set_session_name', arguments: { name: payload.name } });
          } catch (_) {}
        }
        return { name: session.name };
      }

      case 'session.fork': {
        if (!sessionId) throw new Error('sessionId required');
        const session = this.registry.getSession(sessionId);
        if (!session) throw new Error(`Session ${sessionId} not found`);
        const fork = await this.registry.cloneSession(sessionId, payload?.entryId);
        return { sessionId: fork.id };
      }

      case 'session.clone': {
        if (!sessionId) throw new Error('sessionId required');
        const session = this.registry.getSession(sessionId);
        if (!session) throw new Error(`Session ${sessionId} not found`);
        const clone = await this.registry.cloneSession(sessionId);
        return { sessionId: clone.id };
      }

      case 'session.getTree': {
        if (!sessionId) throw new Error('sessionId required');
        const session = this.registry.getSession(sessionId);
        if (!session) throw new Error(`Session ${sessionId} not found`);
        if (session.worker) {
          const res = await session.worker.send({ command: 'get_tree', arguments: {} });
          return res.data;
        }
        return { tree: [] };
      }

      default: {
        const err: any = new Error(`Unsupported command type: ${cmd.type}`);
        err.code = 'COMMAND_REJECTED';
        throw err;
      }
    }
  }
}

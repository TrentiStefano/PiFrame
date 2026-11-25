import type { PcpEventType } from '@piframe/pcp-ts';

export interface PendingUiRequest {
  requestId: string;
  method: string;
  title?: string;
  message?: string;
  dialog: boolean;
  claimedBy: string | null;
  claimedAt: number | null;
  leaseExpiresAt: number | null;
  leaseTimer?: NodeJS.Timeout | null;
  raw: Record<string, unknown>;
}

export interface UiRequestBrokerOptions {
  sessionId: string;
  onEmitEvent: (event: { type: PcpEventType; payload: Record<string, unknown> }) => void;
}

export class UiRequestBroker {
  private onEmitEvent: (event: { type: PcpEventType; payload: Record<string, unknown> }) => void;
  private requests = new Map<string, PendingUiRequest>();

  constructor(opts: UiRequestBrokerOptions) {
    this.onEmitEvent = opts.onEmitEvent;
  }

  public addRequest(raw: Record<string, unknown>): void {
    const rawId = raw.requestId || raw.id;
    if (typeof rawId !== 'string' || !rawId) return;
    const requestId: string = rawId;

    const req: PendingUiRequest = {
      requestId,
      method: String(raw.method || 'confirm'),
      title: typeof raw.title === 'string' ? raw.title : undefined,
      message: typeof raw.message === 'string' ? raw.message : undefined,
      dialog: Boolean(raw.dialog ?? true),
      claimedBy: null,
      claimedAt: null,
      leaseExpiresAt: null,
      leaseTimer: null,
      raw
    };

    this.requests.set(requestId, req);
  }

  public isLocalOnly(requestId: string): boolean {
    return this.requests.get(requestId)?.raw.localOnly === true;
  }

  public claimRequest(
    requestId: string,
    clientId: string,
    leaseDurationMs = 30000
  ): { success: boolean; reason?: string } {
    const req = this.requests.get(requestId);
    if (!req) {
      return { success: false, reason: 'Request not found' };
    }

    const now = Date.now();
    // Check if claimed by another client and lease is still valid
    if (req.claimedBy && req.claimedBy !== clientId && req.leaseExpiresAt && req.leaseExpiresAt > now) {
      return { success: false, reason: 'UI request already claimed by another client' };
    }

    // Cancel existing lease timer if any
    if (req.leaseTimer) {
      clearTimeout(req.leaseTimer);
      req.leaseTimer = null;
    }

    req.claimedBy = clientId;
    req.claimedAt = now;
    req.leaseExpiresAt = now + leaseDurationMs;

    req.leaseTimer = setTimeout(() => {
      this.releaseClaim(requestId, clientId);
    }, leaseDurationMs);

    this.onEmitEvent({
      type: 'ui.claimed',
      payload: { requestId, clientId }
    });

    return { success: true };
  }

  public releaseClaim(requestId: string, clientId: string): void {
    const req = this.requests.get(requestId);
    if (!req || req.claimedBy !== clientId) return;

    if (req.leaseTimer) {
      clearTimeout(req.leaseTimer);
      req.leaseTimer = null;
    }

    req.claimedBy = null;
    req.claimedAt = null;
    req.leaseExpiresAt = null;

    // Broadcast that the request is once again unclaimed
    this.onEmitEvent({
      type: 'ui.claimed',
      payload: { requestId, clientId: null }
    });
  }

  public onClientDisconnected(clientId: string): void {
    for (const [id, req] of this.requests.entries()) {
      if (req.claimedBy === clientId) {
        this.releaseClaim(id, clientId);
      }
    }
  }

  public resolveRequest(
    requestId: string,
    clientId?: string,
    resolution: 'value' | 'confirmed' | 'cancelled' | 'timeout' = 'confirmed'
  ): { success: boolean; reason?: string } {
    const req = this.requests.get(requestId);
    if (!req) {
      return { success: false, reason: 'Request not found' };
    }

    // If a clientId was provided, check if it's the leaseholder (or if unclaimed, claim it)
    if (clientId && req.claimedBy && req.claimedBy !== clientId) {
      const now = Date.now();
      if (req.leaseExpiresAt && req.leaseExpiresAt > now) {
        return { success: false, reason: 'Request is claimed by another client' };
      }
    }

    if (req.leaseTimer) {
      clearTimeout(req.leaseTimer);
      req.leaseTimer = null;
    }

    this.requests.delete(requestId);

    this.onEmitEvent({
      type: 'ui.resolved',
      payload: {
        requestId,
        resolution,
        byClientId: clientId
      }
    });

    return { success: true };
  }

  public cancelAll(reason = 'cancelled'): void {
    for (const [id, req] of this.requests.entries()) {
      if (req.leaseTimer) {
        clearTimeout(req.leaseTimer);
      }
      this.onEmitEvent({
        type: 'ui.resolved',
        payload: {
          requestId: id,
          resolution: 'cancelled',
          reason
        }
      });
    }
    this.requests.clear();
  }

  public getPending(): Array<Record<string, any>> {
    return Array.from(this.requests.values()).map((r) => ({
      ...r.raw,
      requestId: r.requestId,
      method: r.method,
      title: r.title,
      message: r.message,
      dialog: r.dialog,
      claimedBy: r.claimedBy
    }));
  }

  public dispose(): void {
    for (const req of this.requests.values()) {
      if (req.leaseTimer) {
        clearTimeout(req.leaseTimer);
      }
    }
    this.requests.clear();
  }
}

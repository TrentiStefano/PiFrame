import type { PcpResultPayload, PcpResultState } from '@pi-crust/pcp-ts';

export interface CommandRecord {
  commandId: string;
  type: string;
  state: PcpResultState | 'executing';
  createdAt: number;
  resultPayload?: PcpResultPayload;
  waiters: Array<(payload: PcpResultPayload) => void>;
}

export class CommandDeduplicator {
  private records = new Map<string, CommandRecord>();
  private readonly ttlMs = 10 * 60 * 1000; // 10 minutes TTL

  public get(commandId: string): CommandRecord | undefined {
    this.cleanExpired();
    return this.records.get(commandId);
  }

  public register(commandId: string, type: string): CommandRecord {
    this.cleanExpired();
    const record: CommandRecord = {
      commandId,
      type,
      state: 'executing',
      createdAt: Date.now(),
      waiters: []
    };
    this.records.set(commandId, record);
    return record;
  }

  public complete(commandId: string, state: PcpResultState, data?: any, error?: string): PcpResultPayload {
    const record = this.records.get(commandId);
    const payload: PcpResultPayload = {
      state,
      data,
      error
    };
    if (record) {
      record.state = state;
      record.resultPayload = payload;
      for (const waiter of record.waiters) {
        waiter(payload);
      }
      record.waiters = [];
    }
    return payload;
  }

  private cleanExpired(): void {
    const now = Date.now();
    for (const [id, rec] of this.records.entries()) {
      if (now - rec.createdAt > this.ttlMs) {
        this.records.delete(id);
      }
    }
  }
}

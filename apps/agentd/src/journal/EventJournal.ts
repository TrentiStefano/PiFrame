import { ulid } from 'ulid';
import type { PcpEvent, PcpEventType, PcpSnapshotPayload } from '@piframe/pcp-ts';
import { RingBuffer } from './RingBuffer.js';
import { Spill } from './Spill.js';
import { SnapshotBuilder, type SnapshotContext } from './SnapshotBuilder.js';

export interface EventJournalOptions {
  sessionId: string;
  maxEvents?: number;
  snapshotEvery?: number;
  getContext?: () => SnapshotContext;
}

export class EventJournal {
  public readonly sessionId: string;
  private ringBuffer: RingBuffer;
  private spill: Spill;
  private seqCounter = 0;
  private snapshotEvery: number;
  private getContext?: () => SnapshotContext;

  constructor(opts: EventJournalOptions) {
    this.sessionId = opts.sessionId;
    this.ringBuffer = new RingBuffer(opts.maxEvents ?? 2000);
    this.spill = new Spill(opts.sessionId);
    this.snapshotEvery = opts.snapshotEvery ?? 500;
    this.getContext = opts.getContext;

    this.recoverFromSpill();
  }

  private recoverFromSpill(): void {
    const historical = this.spill.readAll();
    if (historical.length > 0) {
      for (const evt of historical) {
        this.ringBuffer.push(evt);
        if (evt.seq > this.seqCounter) {
          this.seqCounter = evt.seq;
        }
      }
    }
  }

  public append(rawEvent: { type: PcpEventType; payload: any }): PcpEvent {
    // Monotonic sequential ID assignment without await
    const seq = ++this.seqCounter;

    const event: PcpEvent = {
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: this.sessionId,
      seq,
      type: rawEvent.type,
      payload: rawEvent.payload
    };

    this.ringBuffer.push(event);
    this.spill.append(event);

    if (seq % this.snapshotEvery === 0 && this.getContext) {
      const snap = SnapshotBuilder.build(this.getContext(), seq);
      this.spill.saveSnapshot(seq, snap);
    }

    return event;
  }

  public getRange(fromSeq: number, toSeq: number): PcpEvent[] {
    const minRing = this.ringBuffer.minSeq;
    if (minRing !== null && fromSeq >= minRing) {
      return this.ringBuffer.getRange(fromSeq, toSeq);
    }

    // Fall back to spill for older events beyond the in-memory ring buffer
    const all = this.spill.readAll();
    return all.filter((e) => e.seq >= fromSeq && e.seq <= toSeq);
  }

  public get minSeq(): number {
    return this.ringBuffer.minSeq ?? (this.seqCounter > 0 ? 1 : 0);
  }

  public get currentSeq(): number {
    return this.seqCounter;
  }

  public buildSnapshot(seq?: number): PcpSnapshotPayload | null {
    if (!this.getContext) return null;
    return SnapshotBuilder.build(this.getContext(), seq ?? this.seqCounter);
  }

  public close(): Promise<void> {
    return this.spill.close();
  }
}

import type { PcpEvent } from '@piframe/pcp-ts';

export class RingBuffer {
  private buffer: PcpEvent[];
  private capacity: number;
  private head = 0;
  private size = 0;

  constructor(capacity: number = 2000) {
    this.capacity = capacity;
    this.buffer = new Array(capacity);
  }

  public push(event: PcpEvent): void {
    if (this.size < this.capacity) {
      this.buffer[this.size++] = event;
    } else {
      this.buffer[this.head] = event;
      this.head = (this.head + 1) % this.capacity;
    }
  }

  /** Reads a slot the ring has already filled; an empty slot inside the live range is a bug. */
  private slot(index: number): PcpEvent {
    const event = this.buffer[index];
    if (event === undefined) {
      throw new Error(`RingBuffer slot ${index} is empty`);
    }
    return event;
  }

  public toArray(): PcpEvent[] {
    if (this.size < this.capacity) {
      return this.buffer.slice(0, this.size);
    }
    const result: PcpEvent[] = [];
    for (let i = 0; i < this.capacity; i++) {
      result.push(this.slot((this.head + i) % this.capacity));
    }
    return result;
  }

  public getRange(fromSeq: number, toSeq: number): PcpEvent[] {
    const all = this.toArray();
    return all.filter((e) => e.seq >= fromSeq && e.seq <= toSeq);
  }

  public get minSeq(): number | null {
    if (this.size === 0) return null;
    if (this.size < this.capacity) return this.slot(0).seq;
    return this.slot(this.head).seq;
  }

  public get maxSeq(): number | null {
    if (this.size === 0) return null;
    const lastIdx = this.size < this.capacity ? this.size - 1 : (this.head + this.capacity - 1) % this.capacity;
    return this.slot(lastIdx).seq;
  }

  public get length(): number {
    return this.size;
  }
}

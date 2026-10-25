import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import type { PcpEvent } from '@piframe/pcp-ts';
import { getPiFrameBaseDir } from '../config/config.js';

export class Spill {
  private sessionId: string;
  private journalDir: string;
  private eventsFile: string;
  private writeStream?: fs.WriteStream;

  constructor(sessionId: string) {
    this.sessionId = sessionId;
    this.journalDir = path.join(getPiFrameBaseDir(), 'journal', sessionId);
    this.eventsFile = path.join(this.journalDir, 'events.jsonl');
    this.init();
  }

  private init(): void {
    try {
      if (!fs.existsSync(this.journalDir)) {
        fs.mkdirSync(this.journalDir, { recursive: true });
      }
      this.writeStream = fs.createWriteStream(this.eventsFile, { flags: 'a', encoding: 'utf8' });
      this.writeStream.on('error', (error) => {
        console.error(`Spill write failed for session ${this.sessionId}:`, error);
        this.writeStream = undefined;
      });
    } catch (err) {
      console.error(`Failed to initialize spill for session ${this.sessionId}:`, err);
    }
  }

  public append(event: PcpEvent): void {
    if (!this.writeStream) return;
    try {
      this.writeStream.write(JSON.stringify(event) + '\n');
    } catch (err) {
      console.error(`Failed to spill event seq=${event.seq}:`, err);
    }
  }

  public readAll(): PcpEvent[] {
    if (!fs.existsSync(this.eventsFile)) {
      return [];
    }
    const events: PcpEvent[] = [];
    try {
      const content = fs.readFileSync(this.eventsFile, 'utf8');
      const lines = content.split('\n');
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const parsed = JSON.parse(line);
          if (parsed.seq !== undefined) {
            events.push(parsed);
          }
        } catch {
          // If a trailing line is corrupted/truncated, skip gracefully
        }
      }
    } catch (err) {
      console.error(`Failed to read spill for session ${this.sessionId}:`, err);
    }
    return events;
  }

  public saveSnapshot(seq: number, snapshot: any): void {
    try {
      const snapFile = path.join(this.journalDir, `snapshot.${seq}.json`);
      const tempFile = `${snapFile}.tmp.${Date.now()}`;
      fs.writeFileSync(tempFile, JSON.stringify(snapshot, null, 2), 'utf8');
      fs.renameSync(tempFile, snapFile);
    } catch (err) {
      console.error(`Failed to save snapshot for session ${this.sessionId} at seq=${seq}:`, err);
    }
  }

  public loadLatestSnapshot(): { seq: number; snapshot: any } | null {
    if (!fs.existsSync(this.journalDir)) return null;
    try {
      const files = fs.readdirSync(this.journalDir);
      const snapFiles = files
        .filter((f) => f.startsWith('snapshot.') && f.endsWith('.json'))
        .map((f) => {
          const m = f.match(/snapshot\.(\d+)\.json/);
          return { file: f, seq: m ? parseInt(m[1], 10) : -1 };
        })
        .filter((s) => s.seq >= 0)
        .sort((a, b) => b.seq - a.seq);

      if (snapFiles.length > 0) {
        const latest = snapFiles[0];
        const content = fs.readFileSync(path.join(this.journalDir, latest.file), 'utf8');
        return { seq: latest.seq, snapshot: JSON.parse(content) };
      }
    } catch (err) {
      console.error(`Failed to load snapshot for session ${this.sessionId}:`, err);
    }
    return null;
  }

  public close(): Promise<void> {
    const stream = this.writeStream;
    this.writeStream = undefined;
    if (!stream || stream.closed) return Promise.resolve();
    return new Promise<void>((resolve) => {
      stream.once('close', resolve);
      stream.end();
    });
  }
}

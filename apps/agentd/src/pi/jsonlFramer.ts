import { StringDecoder } from 'node:string_decoder';

export interface JsonlParseResult<T = any> {
  ok: boolean;
  value?: T;
  raw: string;
  error?: Error;
}

export class JsonlFramer {
  private buffer: Buffer[] = [];
  private totalLength = 0;
  private decoder = new StringDecoder('utf8');

  /**
   * Pushes incoming raw bytes and yields any parsed JSON objects separated strictly by LF (\n).
   * Note: We NEVER use readline because U+2028 and U+2029 are valid inside JSON strings and
   * readline breaks on them.
   */
  public push(chunk: Buffer): JsonlParseResult[] {
    const results: JsonlParseResult[] = [];
    let start = 0;

    for (let i = 0; i < chunk.length; i++) {
      if (chunk[i] === 0x0A) { // LF '\n'
        let lineBuffer: Buffer;
        if (this.totalLength > 0) {
          this.buffer.push(chunk.subarray(start, i));
          lineBuffer = Buffer.concat(this.buffer);
          this.buffer = [];
          this.totalLength = 0;
        } else {
          lineBuffer = chunk.subarray(start, i);
        }

        start = i + 1;

        // Strip optional trailing CR (\r)
        if (lineBuffer.length > 0 && lineBuffer[lineBuffer.length - 1] === 0x0D) {
          lineBuffer = lineBuffer.subarray(0, lineBuffer.length - 1);
        }

        const raw = this.decoder.write(lineBuffer) + this.decoder.end();
        this.decoder = new StringDecoder('utf8');

        // Ignore empty lines
        if (raw.trim().length === 0) {
          continue;
        }

        try {
          const parsed = JSON.parse(raw);
          results.push({ ok: true, value: parsed, raw });
        } catch (err) {
          results.push({ ok: false, error: err as Error, raw });
        }
      }
    }

    if (start < chunk.length) {
      const remaining = chunk.subarray(start);
      this.buffer.push(remaining);
      this.totalLength += remaining.length;
    }

    return results;
  }

  public flush(): JsonlParseResult[] {
    const results: JsonlParseResult[] = [];
    if (this.totalLength > 0) {
      let lineBuffer = Buffer.concat(this.buffer);
      this.buffer = [];
      this.totalLength = 0;

      if (lineBuffer.length > 0 && lineBuffer[lineBuffer.length - 1] === 0x0D) {
        lineBuffer = lineBuffer.subarray(0, lineBuffer.length - 1);
      }

      const raw = this.decoder.write(lineBuffer) + this.decoder.end();
      if (raw.trim().length > 0) {
        try {
          const parsed = JSON.parse(raw);
          results.push({ ok: true, value: parsed, raw });
        } catch (err) {
          results.push({ ok: false, error: err as Error, raw });
        }
      }
    }
    return results;
  }
}

import type { Server } from 'node:http';
import type { RawData } from 'ws';

/** The payload of a PCP frame. Each test reads the fields it expects through `dataOf` or a typed view, so a wrong shape fails that assertion. */
export type Payload = Record<string, unknown>;

/** A PCP frame as the daemon sends it. The envelope fields the tests route on are typed. */
export interface Frame {
  kind?: string;
  type?: string;
  id?: string;
  commandId?: string;
  sessionId?: string;
  seq?: number;
  payload: Payload;
  [key: string]: unknown;
}

/** Decodes one JSON text frame received from the daemon. */
export function parseFrame(data: RawData): Frame {
  return JSON.parse(data.toString());
}

/** The `data` of a command result payload, viewed as the type the test expects. */
export function dataOf<T>(frame: Frame): T {
  return frame.payload.data as T;
}

/** The TCP port a listening server is bound to. Throws when the server is not listening on a TCP port. */
export function listeningPort(server: Server): number {
  const addr = server.address();
  if (addr === null || typeof addr === 'string') throw new Error('server is not listening on a TCP port');
  return addr.port;
}

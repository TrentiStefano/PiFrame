import { ulid } from 'ulid';
import type {
  PcpEnvelope,
  ProtocolKind,
  PcpMessage
} from './types.js';

export function generateId(prefix?: string): string {
  const id = ulid();
  return prefix ? `${prefix}_${id}` : id;
}

export function makeEnvelope<T = Record<string, unknown>>(
  kind: ProtocolKind,
  type: string,
  payload: T,
  options?: {
    id?: string;
    ts?: number;
    commandId?: string;
    sessionId?: string;
    seq?: number;
  }
): PcpEnvelope<T> {
  return {
    protocol: 1,
    kind,
    id: options?.id || generateId(kind),
    ts: options?.ts ?? Date.now(),
    ...(options?.commandId ? { commandId: options.commandId } : {}),
    ...(options?.sessionId ? { sessionId: options.sessionId } : {}),
    ...(options?.seq !== undefined ? { seq: options.seq } : {}),
    type,
    payload
  };
}

export function encode(msg: PcpMessage): string {
  return JSON.stringify(msg);
}

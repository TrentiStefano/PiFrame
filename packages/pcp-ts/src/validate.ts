import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import type { ClientMessage, PcpEnvelope, PcpError, PcpMessage } from './types.js';

const ajv = new (Ajv2020 as any)({ strict: false, allErrors: true });
(addFormats as any)(ajv);

export type Result<T, E> =
  | { ok: true; value: T }
  | { ok: false; error: E };

export function isEnvelope(value: unknown): value is PcpEnvelope {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    v.protocol === 1 &&
    typeof v.kind === 'string' &&
    typeof v.id === 'string' &&
    typeof v.ts === 'number' &&
    typeof v.type === 'string' &&
    typeof v.payload === 'object' &&
    v.payload !== null
  );
}

export function validateIncoming(obj: unknown): Result<ClientMessage, PcpError> {
  if (!isEnvelope(obj)) {
    return {
      ok: false,
      error: {
        protocol: 1,
        kind: 'error',
        id: `err_${Date.now()}`,
        ts: Date.now(),
        type: 'error',
        payload: {
          code: 'INVALID_MESSAGE',
          message: 'Message does not conform to PCP/1 envelope structure',
          retryable: false
        }
      }
    };
  }

  // Kind-specific validations
  if (obj.kind === 'hello') {
    const p = obj.payload as Record<string, unknown>;
    if (!p || typeof p.token !== 'string' || typeof p.client !== 'object' || p.encoding !== 'json') {
      return {
        ok: false,
        error: {
          protocol: 1,
          kind: 'error',
          id: `err_${Date.now()}`,
          ts: Date.now(),
          type: 'error',
          payload: {
            code: 'INVALID_MESSAGE',
            message: 'Invalid hello payload: required token, client, and encoding=json',
            retryable: false
          }
        }
      };
    }
    return { ok: true, value: obj as ClientMessage };
  }

  if (obj.kind === 'command') {
    if (!obj.commandId || typeof obj.commandId !== 'string') {
      return {
        ok: false,
        error: {
          protocol: 1,
          kind: 'error',
          id: `err_${Date.now()}`,
          ts: Date.now(),
          type: 'error',
          payload: {
            code: 'INVALID_MESSAGE',
            message: 'Command message must include commandId for idempotency',
            retryable: false
          }
        }
      };
    }
    return { ok: true, value: obj as ClientMessage };
  }

  if (obj.kind === 'pong') {
    return { ok: true, value: obj as ClientMessage };
  }

  return {
    ok: false,
    error: {
      protocol: 1,
      kind: 'error',
      id: `err_${Date.now()}`,
      ts: Date.now(),
      type: 'error',
      payload: {
        code: 'INVALID_MESSAGE',
        message: `Unexpected kind '${obj.kind}' sent by client`,
        retryable: false
      }
    }
  };
}

export function parseIncoming(raw: string): Result<ClientMessage, PcpError> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      error: {
        protocol: 1,
        kind: 'error',
        id: `err_${Date.now()}`,
        ts: Date.now(),
        type: 'error',
        payload: {
          code: 'INVALID_MESSAGE',
          message: `Malformed JSON frame: ${msg}`,
          retryable: false
        }
      }
    };
  }

  return validateIncoming(parsed);
}

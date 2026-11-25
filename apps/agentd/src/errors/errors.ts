/**
 * Helpers for errors that cross a `catch` boundary. A caught value is `unknown`: these
 * functions read its message and code without asserting a shape the runtime does not guarantee.
 */

/** An Error that carries a machine-readable code (for example `SESSION_NOT_FOUND`) and optional UI hints. */
export interface CodedError extends Error {
  code?: string;
  hint?: string;
  details?: unknown;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/** A named property of a value, or undefined when the value is not an object or lacks it. */
export function readProperty(value: unknown, key: string): unknown {
  return isRecord(value) ? value[key] : undefined;
}

/** The `code` property of a caught value, or undefined when it has none. */
export function errorCode(error: unknown): unknown {
  return readProperty(error, 'code');
}

/** The `message` property of a caught value when it is a string, otherwise undefined. */
export function errorMessage(error: unknown): string | undefined {
  if (!isRecord(error)) return undefined;
  return typeof error.message === 'string' ? error.message : undefined;
}

/** Creates an Error with a code set, for throwing a rejection the dispatcher can classify. */
export function createCodedError(message: string, code?: string): CodedError {
  const error: CodedError = new Error(message);
  if (code !== undefined) error.code = code;
  return error;
}

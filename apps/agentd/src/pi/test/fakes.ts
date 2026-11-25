// Shared helpers for the Pi module tests. They read values whose shape a test checks at run time, without
// asserting a type: a missing or non-object step yields undefined, so the assertion that follows fails.

/** Reads a nested field of a value; a missing or non-object step yields undefined. */
export function at(value: unknown, ...path: string[]): unknown {
  let current: unknown = value;
  for (const key of path) {
    if (typeof current !== 'object' || current === null) return undefined;
    current = Reflect.get(current, key);
  }
  return current;
}

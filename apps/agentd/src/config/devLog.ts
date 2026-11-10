import * as fs from 'node:fs';
import { format } from 'node:util';
import { getLogPath } from './runtime.js';

/**
 * Reports event-loop stalls: a timer scheduled every `intervalMs` that fires late by at least `thresholdMs`
 * means something blocked the loop (sync file reads, long JSON parses) for that long.
 */
export function startEventLoopMonitor(
  report: (blockedMs: number) => void,
  { intervalMs = 250, thresholdMs = 500 } = {},
): () => void {
  let last = Date.now();
  const timer = setInterval(() => {
    const now = Date.now();
    const late = now - last - intervalMs;
    last = now;
    if (late >= thresholdMs) report(late);
  }, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}

let devWrite: ((level: string, message: string) => void) | null = null;

/** Dev-only: records a command that took at least `thresholdMs`, so a stall can be matched to what the app asked for. */
export function reportSlowCommand(type: string, sessionId: string | undefined, ms: number, thresholdMs = 300): void {
  if (devWrite && ms >= thresholdMs) devWrite('slow', `command ${type} session=${sessionId ?? '-'} took ${ms}ms`);
}

/**
 * Dev-only: mirrors console output and loop stalls into runtime/daemon.log. Only the dev launcher sets
 * PIFRAME_DEV_LOG=1, so release daemons write nothing extra. Writes are synchronous so lines survive a crash.
 */
export function enableDevFileLog(
  env: NodeJS.ProcessEnv = process.env,
  file: string = getLogPath(),
): (() => void) | null {
  if (env.PIFRAME_DEV_LOG !== '1') return null;
  const write = (level: string, message: string) => {
    fs.appendFileSync(file, `${new Date().toISOString()} ${level} ${message}\n`);
  };
  devWrite = write;
  write('start', `--- daemon pid=${process.pid} ---`);
  const levels = ['log', 'info', 'warn', 'error'] as const;
  const originals = levels.map((level) => console[level]);
  levels.forEach((level, index) => {
    console[level] = (...args: unknown[]) => {
      originals[index].apply(console, args);
      write(level, format(...args));
    };
  });
  const stopMonitor = startEventLoopMonitor((blockedMs) => write('stall', `event loop blocked for ${blockedMs}ms`));
  return () => {
    stopMonitor();
    devWrite = null;
    levels.forEach((level, index) => { console[level] = originals[index]; });
  };
}

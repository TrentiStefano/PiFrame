import * as fs from 'node:fs';
import * as inspector from 'node:inspector';
import { format } from 'node:util';
import { getLogPath } from './runtime.js';

/**
 * Reports event-loop stalls: a timer scheduled every `intervalMs` that fires late by at least `thresholdMs`
 * means something blocked the loop (sync file reads, long JSON parses) for that long.
 */
export function startEventLoopMonitor(
  report: (blockedMs: number) => void,
  { intervalMs = 250, thresholdMs = 500 } = {}
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

// Milliseconds in one second, to turn the profile length (in seconds) into a timer delay.
const MS_PER_SECOND = 1000;

/**
 * Dev-only: samples the CPU for `seconds` from daemon start and writes a .cpuprofile file, so a blocked
 * event loop can be matched to the functions that ran. Off unless PIFRAME_DEV_PROFILE_SECONDS is set.
 */
export function startDevCpuProfile(
  env: NodeJS.ProcessEnv,
  file: string,
  onDone: (file: string) => void = () => {}
): boolean {
  const seconds = Number(env.PIFRAME_DEV_PROFILE_SECONDS);
  if (!Number.isFinite(seconds) || seconds <= 0) return false;
  const session = new inspector.Session();
  session.connect();
  session.post('Profiler.enable');
  session.post('Profiler.start');
  setTimeout(() => {
    session.post('Profiler.stop', (error, result) => {
      if (!error) fs.writeFileSync(file, JSON.stringify(result.profile));
      session.disconnect();
      onDone(file);
    });
  }, seconds * MS_PER_SECOND).unref();
  return true;
}

let logWrite: ((level: string, message: string) => void) | null = null;

/** Records a command that took at least `thresholdMs`, so a slow screen can be matched to what the app asked for. */
export function reportSlowCommand(type: string, sessionId: string | undefined, ms: number, thresholdMs = 300): void {
  if (logWrite && ms >= thresholdMs) logWrite('slow', `command ${type} session=${sessionId ?? '-'} took ${ms}ms`);
}

/** The size at which runtime/daemon.log rotates, and how many files it keeps (docs/install.md). */
export const DAEMON_LOG_MAX_BYTES = 5 * 1024 * 1024;
export const DAEMON_LOG_FILES = 5;

/** Appends lines to `file`, rotating to `file.1` ... `file.<files - 1>` before a line would pass `maxBytes`. */
function rotatingAppender(file: string, maxBytes: number, files: number): (line: string) => void {
  let size = fs.existsSync(file) ? fs.statSync(file).size : 0;
  return (line) => {
    const bytes = Buffer.byteLength(line);
    if (size > 0 && size + bytes > maxBytes) {
      for (let i = files - 1; i >= 1; i--) {
        const from = i === 1 ? file : `${file}.${i - 1}`;
        if (fs.existsSync(from)) fs.renameSync(from, `${file}.${i}`);
      }
      size = 0;
    }
    fs.appendFileSync(file, line);
    size += bytes;
  };
}

/**
 * Every daemon writes runtime/daemon.log: its start, slow commands and event-loop stalls, so a slow screen leaves
 * evidence on the user's machine (#114). The log stays local (ADR 0016) and rotates across `files` files of
 * `maxBytes`. Console output is mirrored only in dev builds (PIFRAME_DEV_LOG=1, set by the dev launcher and the
 * harness), since it can carry paths and other details. Writes are synchronous so lines survive a crash.
 */
export function enableDaemonFileLog(
  env: NodeJS.ProcessEnv = process.env,
  file: string = getLogPath(),
  { maxBytes = DAEMON_LOG_MAX_BYTES, files = DAEMON_LOG_FILES } = {}
): () => void {
  const append = rotatingAppender(file, maxBytes, files);
  const write = (level: string, message: string) => {
    try {
      append(`${new Date().toISOString()} ${level} ${message}\n`);
    } catch {
      // A full or read-only disk must not stop the daemon.
    }
  };
  logWrite = write;
  write('start', `--- daemon pid=${process.pid} ---`);
  const stopMonitor = startEventLoopMonitor((blockedMs) => write('stall', `event loop blocked for ${blockedMs}ms`));
  const restoreConsole = env.PIFRAME_DEV_LOG === '1' ? mirrorConsole(write) : () => {};
  return () => {
    stopMonitor();
    restoreConsole();
    logWrite = null;
  };
}

/** Dev-only: copies console output into the log. Returns the function that restores the console. */
function mirrorConsole(write: (level: string, message: string) => void): () => void {
  const levels = ['log', 'info', 'warn', 'error'] as const;
  const originals = {
    log: console.log,
    info: console.info,
    warn: console.warn,
    error: console.error
  } satisfies Record<(typeof levels)[number], unknown>;
  levels.forEach((level) => {
    console[level] = (...args: unknown[]) => {
      originals[level].apply(console, args);
      write(level, format(...args));
    };
  });
  return () => {
    levels.forEach((level) => {
      console[level] = originals[level];
    });
  };
}

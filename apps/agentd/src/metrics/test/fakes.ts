import { EventEmitter } from 'node:events';
import type { ChildProcess, ExecFileOptions } from 'node:child_process';
import type { WebSocket } from 'ws';
import type { ExecFileFn } from '../gpu/MacIoregGpuProvider.js';
import type { SpawnChildProcessFn } from '../gpu/NvidiaGpuProvider.js';
import type { GpuProviderFactory } from '../gpu/GpuProviderFactory.js';
import type { Connection } from '../../server/connection.js';

// Test doubles for the metrics tests. Like the command fakes, each builder takes only the members a
// test drives and makes one downcast to the production type.

/** A socket double that records the frames sent to it. */
export class MockWebSocket extends EventEmitter {
  public readyState: 0 | 1 | 2 | 3 = 1;
  public sentMessages: string[] = [];

  public send(data: string, ...rest: unknown[]): void {
    this.sentMessages.push(data);
    const cb = rest.find((arg) => typeof arg === 'function');
    if (typeof cb === 'function') cb();
  }

  public close(): void {
    this.readyState = 3;
    this.emit('close');
  }
}

/** The socket a Connection expects: the mock implements the members the daemon reads. */
export function asSocket(mock: MockWebSocket): WebSocket {
  const socket: Partial<Pick<WebSocket, 'readyState' | 'send' | 'close'>> = mock;
  return socket as WebSocket;
}

export function fakeConnection(members: Partial<Connection>): Connection {
  return members as Connection;
}

/**
 * A timer handle for the sampler's timer provider. It is a real Timeout, cleared at once, so it is the
 * production handle type and identity checks against it are exact.
 */
export function timerHandle(): NodeJS.Timeout {
  const timer = setTimeout(() => {}, 0);
  clearTimeout(timer);
  return timer;
}

/** A GPU provider factory double; the sampler calls only `getProvider`. */
export function gpuFactoryDouble(members: { getProvider: () => Promise<unknown> }): GpuProviderFactory {
  return members as GpuProviderFactory;
}

/** The child-process members the GPU providers read: stdout, kill and the exit event. */
export type ChildDouble = EventEmitter & { kill?: () => boolean; stdout?: unknown };

/** A child-process double typed as the ChildProcess the spawn seam returns. */
export function asChild(child: ChildDouble): ChildProcess {
  return child as ChildProcess;
}

/** A spawn seam double; the providers call it with a command and arguments and read the child it returns. */
export function spawnDouble(spawnFn: (command: string, args: readonly string[]) => ChildDouble): SpawnChildProcessFn {
  return spawnFn as SpawnChildProcessFn;
}

type ExecFileCallback = (error: Error | null, stdout: string, stderr: string) => void;

/** An execFile seam double; the providers call it with file, arguments, options and a callback. */
export function execFileDouble(
  execFileFn: (
    file: string,
    args: readonly string[],
    options: ExecFileOptions,
    callback: ExecFileCallback
  ) => ChildDouble
): ExecFileFn {
  return execFileFn as ExecFileFn;
}

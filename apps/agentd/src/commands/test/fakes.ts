import { EventEmitter } from 'node:events';
import type { PcpCommand, PcpCommandType, PcpEnvelope } from '@piframe/pcp-ts';
import type { WebSocket } from 'ws';
import type { PiPackageOperations } from '../../pi/PiPackageService.js';
import type { RemoteManager } from '../../remote/RemoteManager.js';
import type { StdioPiTransport } from '../../pi/StdioPiTransport.js';
import type { Connection } from '../../server/connection.js';
import type { ConnectionManager } from '../../server/wsServer.js';
import type { SessionIndex } from '../../sessions/SessionIndex.js';
import type { SessionRegistry } from '../../sessions/SessionRegistry.js';
import type { UiRequestBroker } from '../../ui/UiRequestBroker.js';

// Test doubles for the command dispatcher. Each builder takes only the members a test drives; the rest
// are absent at run time, as the earlier untyped fakes were. Each builder makes one downcast from its
// partial parameter type to the production type, so test files need no escape-hatch casts.

/** A socket double that records the frames sent to it. */
export class MockWebSocket extends EventEmitter {
  public readyState: 0 | 1 | 2 | 3 = 1;
  public sentMessages: string[] = [];
  public closedCode?: number;
  public closedReason?: string;

  public send(data: string, ...rest: unknown[]): void {
    this.sentMessages.push(data);
    const cb = rest.find((arg) => typeof arg === 'function');
    if (typeof cb === 'function') cb();
  }

  public close(code: number, reason: string): void {
    this.readyState = 3;
    this.closedCode = code;
    this.closedReason = reason;
    this.emit('close');
  }
}

/** The socket a Connection expects: the mock implements the members the daemon reads. */
export function asSocket(mock: MockWebSocket): WebSocket {
  const socket: Partial<Pick<WebSocket, 'readyState' | 'send' | 'close'>> = mock;
  return socket as WebSocket;
}

export function fakeWorker(members: Partial<StdioPiTransport>): StdioPiTransport {
  return members as StdioPiTransport;
}

export function fakeRegistry(members: Partial<SessionRegistry>): SessionRegistry {
  return members as SessionRegistry;
}

/** A session index double for dispatcher paths that read it; these tests never query it. */
export function fakeIndex(): SessionIndex {
  return {} as SessionIndex;
}

/** Boundary double for a service the tests reach only through a few members; each supplied member is taken as given. */
type Loose<T> = { [K in keyof T]?: unknown };

export function fakePiPackages(members: Loose<PiPackageOperations>): PiPackageOperations {
  return members as PiPackageOperations;
}

export function fakeUiBroker(members: Partial<UiRequestBroker>): UiRequestBroker {
  return members as UiRequestBroker;
}

export function fakeRemoteManager(members: Loose<RemoteManager>): RemoteManager {
  return members as RemoteManager;
}

export function fakeConnection(members: Partial<Connection>): Connection {
  return members as Connection;
}

export function fakeConnectionManager(members: Partial<ConnectionManager>): ConnectionManager {
  return members as ConnectionManager;
}

/** A message the daemon sent to a connection, as the tests read it back. */
export type SentMessage = PcpEnvelope;

/** A command envelope as a client sends it. */
export function commandEnvelope(
  type: PcpCommandType,
  payload: Record<string, unknown>,
  options: { id: string; commandId: string; sessionId?: string }
): PcpCommand {
  return {
    protocol: 1,
    kind: 'command',
    id: options.id,
    ts: Date.now(),
    commandId: options.commandId,
    type,
    sessionId: options.sessionId,
    payload
  };
}

/** Parses a message the connection received; string frames are JSON, objects are taken as they are. */
export function parseSent(message: string | object): SentMessage {
  return (typeof message === 'string' ? JSON.parse(message) : message) as SentMessage;
}

/** Reads a nested field of a value; a missing or non-object step yields undefined. */
export function at(value: unknown, ...path: string[]): unknown {
  let current: unknown = value;
  for (const key of path) {
    if (typeof current !== 'object' || current === null) return undefined;
    current = Reflect.get(current, key);
  }
  return current;
}

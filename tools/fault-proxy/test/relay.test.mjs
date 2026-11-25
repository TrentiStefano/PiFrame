import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket, WebSocketServer } from 'ws';
import { FaultProxy } from '../dist/FaultProxy.js';

/** Resolves with `true` when the socket closes, or `false` if it stays open for `ms`. */
const closedWithin = (ws, ms) =>
  new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), ms);
    ws.once('close', () => {
      clearTimeout(timer);
      resolve(true);
    });
  });

/** Resolves once a socket is open. */
const opened = (ws) =>
  new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });

test('a throwing send on the relayed client socket is logged and closes the relay, with no unhandled rejection', async () => {
  const upstream = new WebSocketServer({ port: 0, host: '127.0.0.1' });
  await new Promise((resolve) => upstream.once('listening', resolve));
  const upstreamPort = upstream.address().port;
  const proxy = new FaultProxy({ targetPort: upstreamPort });
  const proxyPort = await proxy.start();

  // The proxy-side client socket is the one whose local port is the proxy's port. Only its send throws.
  const realSend = WebSocket.prototype.send;
  let armed = false;
  WebSocket.prototype.send = function patchedSend(...args) {
    if (armed && this._socket && this._socket.localPort === proxyPort) {
      throw new Error('simulated send failure');
    }
    return realSend.apply(this, args);
  };

  const rejections = [];
  const onRejection = (reason) => rejections.push(reason);
  process.on('unhandledRejection', onRejection);

  const logged = [];
  const realError = console.error;
  console.error = (...args) => logged.push(args);

  upstream.on('connection', (ws) => {
    armed = true;
    ws.send('frame-from-upstream');
  });

  const client = new WebSocket(`ws://127.0.0.1:${proxyPort}/`);
  try {
    await opened(client);
    const relayClosed = await closedWithin(client, 2000);
    // Let the microtask queue drain so a rejection from the relay would surface.
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepEqual(rejections, [], 'relay must not leave an unhandled rejection');
    assert.ok(logged.length > 0, 'the failed relay is logged');
    assert.equal(relayClosed, true, 'the failed relay closes the client connection');
  } finally {
    console.error = realError;
    process.off('unhandledRejection', onRejection);
    WebSocket.prototype.send = realSend;
    client.terminate();
    await proxy.close();
    await new Promise((resolve) => upstream.close(resolve));
  }
});

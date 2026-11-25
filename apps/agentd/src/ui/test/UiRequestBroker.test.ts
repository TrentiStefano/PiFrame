import test from 'node:test';
import * as assert from 'node:assert';
import { UiRequestBroker, type UiRequestBrokerOptions } from '../UiRequestBroker.js';

type BrokerEvent = Parameters<UiRequestBrokerOptions['onEmitEvent']>[0];

test('UiRequestBroker: claim, conflict, and resolve lifecycle', async () => {
  const events: BrokerEvent[] = [];
  const broker = new UiRequestBroker({
    sessionId: 's_test',
    onEmitEvent: (evt) => events.push(evt)
  });

  // 1. Add a request
  broker.addRequest({
    requestId: 'req_1',
    method: 'confirm',
    title: 'Run command?',
    message: 'Do you want to run rm -rf /?',
    dialog: true
  });

  assert.strictEqual(broker.getPending().length, 1);
  assert.strictEqual(broker.getPending()[0]!.claimedBy, null);

  // 2. Client 1 claims request
  const claim1 = broker.claimRequest('req_1', 'client_1', 1000);
  assert.strictEqual(claim1.success, true);
  assert.strictEqual(broker.getPending()[0]!.claimedBy, 'client_1');

  // Verify event emitted
  const claimedEvt = events.find((e) => e.type === 'ui.claimed');
  assert.ok(claimedEvt);
  assert.strictEqual(claimedEvt.payload.clientId, 'client_1');

  // 3. Client 2 tries to claim before lease expiry -> rejected
  const claim2 = broker.claimRequest('req_1', 'client_2', 1000);
  assert.strictEqual(claim2.success, false);
  assert.match(claim2.reason || '', /already claimed/i);

  // 4. Client 1 resolves the request
  const resolveRes = broker.resolveRequest('req_1', 'client_1', 'confirmed');
  assert.strictEqual(resolveRes.success, true);
  assert.strictEqual(broker.getPending().length, 0);

  const resolvedEvt = events.find((e) => e.type === 'ui.resolved');
  assert.ok(resolvedEvt);
  assert.strictEqual(resolvedEvt.payload.resolution, 'confirmed');

  broker.dispose();
});

test('UiRequestBroker: lease expiration returns request to unclaimed', async () => {
  const events: BrokerEvent[] = [];
  const broker = new UiRequestBroker({
    sessionId: 's_test_expiry',
    onEmitEvent: (evt) => events.push(evt)
  });

  broker.addRequest({
    requestId: 'req_2',
    method: 'input',
    title: 'Enter API Key',
    dialog: true
  });

  // Short lease duration of 50ms
  broker.claimRequest('req_2', 'client_temp', 50);
  assert.strictEqual(broker.getPending()[0]!.claimedBy, 'client_temp');

  // Wait 70ms for lease to expire
  await new Promise((r) => setTimeout(r, 70));

  // Request should now be unclaimed
  assert.strictEqual(broker.getPending()[0]!.claimedBy, null);

  // Now client 2 can claim it
  const claim2 = broker.claimRequest('req_2', 'client_next', 1000);
  assert.strictEqual(claim2.success, true);
  assert.strictEqual(broker.getPending()[0]!.claimedBy, 'client_next');

  broker.dispose();
});

test('UiRequestBroker: numeric request ids and non-string title/message pass through as Pi sent them', () => {
  const events: BrokerEvent[] = [];
  const broker = new UiRequestBroker({
    sessionId: 's_test',
    onEmitEvent: (evt) => events.push(evt)
  });

  const title = 42;
  const message = { text: 'Proceed?' };
  broker.addRequest({ id: 7, method: 'select', title, message, dialog: true });

  const pending = broker.getPending();
  assert.strictEqual(pending.length, 1);
  assert.strictEqual(pending[0]!.requestId, 7);
  assert.strictEqual(pending[0]!.title, title);
  assert.strictEqual(pending[0]!.message, message);

  assert.deepStrictEqual(broker.claimRequest(7, 'client_1', 1000), { success: true });
  assert.strictEqual(broker.isLocalOnly(7), false);
  assert.deepStrictEqual(broker.resolveRequest(7, 'client_1'), { success: true });
  assert.strictEqual(broker.getPending().length, 0);
  assert.strictEqual(events.at(-1)?.type, 'ui.resolved');
  assert.strictEqual(events.at(-1)?.payload.requestId, 7);
  broker.dispose();
});

test('UiRequestBroker: requests without a usable id are ignored', () => {
  const broker = new UiRequestBroker({ sessionId: 's_test', onEmitEvent: () => {} });
  broker.addRequest({ method: 'confirm' });
  broker.addRequest({ requestId: 0, method: 'confirm' });
  broker.addRequest({ requestId: { id: 'x' }, method: 'confirm' });
  assert.strictEqual(broker.getPending().length, 0);
  broker.dispose();
});

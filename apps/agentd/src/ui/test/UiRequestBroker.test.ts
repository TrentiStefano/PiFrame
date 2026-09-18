import test from 'node:test';
import * as assert from 'node:assert';
import { UiRequestBroker } from '../UiRequestBroker.js';

test('UiRequestBroker: claim, conflict, and resolve lifecycle', async () => {
  const events: any[] = [];
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
  assert.strictEqual(broker.getPending()[0].claimedBy, null);

  // 2. Client 1 claims request
  const claim1 = broker.claimRequest('req_1', 'client_1', 1000);
  assert.strictEqual(claim1.success, true);
  assert.strictEqual(broker.getPending()[0].claimedBy, 'client_1');

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
  const events: any[] = [];
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
  assert.strictEqual(broker.getPending()[0].claimedBy, 'client_temp');

  // Wait 70ms for lease to expire
  await new Promise((r) => setTimeout(r, 70));

  // Request should now be unclaimed
  assert.strictEqual(broker.getPending()[0].claimedBy, null);

  // Now client 2 can claim it
  const claim2 = broker.claimRequest('req_2', 'client_next', 1000);
  assert.strictEqual(claim2.success, true);
  assert.strictEqual(broker.getPending()[0].claimedBy, 'client_next');

  broker.dispose();
});

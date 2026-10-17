import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { RemoteAuthManager, MAX_PAIRED_DEVICES } from '../RemoteAuthManager.js';

test('RemoteAuthManager: generates pairing secret, pairs, and consumes single-use secret', () => {
  const tmpFile = path.join(os.tmpdir(), `pi_test_dev_${Date.now()}_${Math.random()}.json`);
  const auth = new RemoteAuthManager(tmpFile);

  const pairing = auth.generatePairing(60000);
  assert.ok(pairing.secret.startsWith('pair_tok_'));
  assert.ok(pairing.secret.length >= 40);
  assert.ok(pairing.expiresAt > Date.now());

  // Pairing by secret
  const result = auth.pair(pairing.secret, 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)', '198.51.100.1', 'view');
  assert.ok(result.deviceId.startsWith('dev_'));
  assert.ok(result.deviceToken.startsWith('rem_dev_'));
  assert.strictEqual(result.device.name, 'Apple iOS Device');
  assert.strictEqual(result.device.mode, 'view');

  // Verify single-use: pairing session has been consumed
  assert.throws(
    () => auth.pair(pairing.secret, 'attacker', '198.51.100.2'),
    /Pairing session expired or not initiated/
  );

  // Device token is verifiable
  const verified = auth.verifyDeviceToken(result.deviceToken);
  assert.ok(verified !== null);
  assert.strictEqual(verified?.deviceId, result.deviceId);
  assert.strictEqual(verified?.mode, 'view');

  // Unrecognized token fails
  assert.strictEqual(auth.verifyDeviceToken('rem_dev_invalid_token'), null);

  // Persistence check: raw deviceToken secret is NEVER on disk, only SHA-256 tokenHash
  auth.flush();
  const fileContent = fs.readFileSync(tmpFile, 'utf8');
  assert.strictEqual(fileContent.includes(result.deviceToken), false);
  const parsed = JSON.parse(fileContent);
  assert.ok(/^[a-f0-9]{64}$/.test(parsed.devices[0].tokenHash));

  // Cleanup
  try { fs.unlinkSync(tmpFile); } catch {}
});

test('RemoteAuthManager: rate limiting locks out IP after 5 failed attempts', () => {
  const tmpFile = path.join(os.tmpdir(), `pi_test_dev_${Date.now()}_${Math.random()}.json`);
  const auth = new RemoteAuthManager(tmpFile);
  auth.generatePairing(60000);

  const ip = '198.51.100.42';

  for (let i = 0; i < 4; i++) {
    assert.throws(
      () => auth.pair('wrong_secret', undefined, ip),
      /Invalid pairing secret/
    );
  }

  // 5th attempt triggers lockout and consumes/destroys the pairing secret
  assert.throws(
    () => auth.pair('wrong_secret', undefined, ip),
    /Invalid pairing secret/
  );

  // 6th attempt is blocked by rate limiting
  assert.throws(
    () => auth.pair('wrong_secret', undefined, ip),
    /Too many failed pairing attempts/
  );

  try { fs.unlinkSync(tmpFile); } catch {}
});

test('RemoteAuthManager: 5 global failed attempts destroy active pairing for everyone', () => {
  const tmpFile = path.join(os.tmpdir(), `pi_test_dev_${Date.now()}_${Math.random()}.json`);
  const auth = new RemoteAuthManager(tmpFile);
  const p = auth.generatePairing(60000);

  // 4 failed attempts from 4 different IPs
  for (let i = 1; i <= 4; i++) {
    assert.throws(
      () => auth.pair('guessed_secret', undefined, `10.0.0.${i}`),
      /Invalid pairing secret/
    );
  }

  // Active pairing is still present
  assert.ok(auth.getActivePairing() !== null);

  // 5th attempt burns the pairing secret globally
  assert.throws(
    () => auth.pair('guessed_secret', undefined, '10.0.0.5'),
    /Invalid pairing secret/
  );

  // The pairing secret is now destroyed; even legitimate client cannot use it
  assert.strictEqual(auth.getActivePairing(), null);
  assert.throws(
    () => auth.pair(p.secret, undefined, '10.0.0.99'),
    /Pairing session expired or not initiated/
  );

  try { fs.unlinkSync(tmpFile); } catch {}
});

test('RemoteAuthManager: enforces max 10 paired devices limit', () => {
  const tmpFile = path.join(os.tmpdir(), `pi_test_dev_${Date.now()}_${Math.random()}.json`);
  const auth = new RemoteAuthManager(tmpFile);

  for (let i = 0; i < MAX_PAIRED_DEVICES; i++) {
    const p = auth.generatePairing(60000);
    auth.pair(p.secret, `Device ${i}`, `10.1.0.${i}`);
  }
  assert.strictEqual(auth.getPairedDevices().length, 10);

  // 11th device pairing must be rejected with REMOTE_DEVICE_LIMIT
  const pOverflow = auth.generatePairing(60000);
  assert.throws(
    () => auth.pair(pOverflow.secret, 'Device Overflow', '10.1.0.99'),
    /Maximum number of paired devices reached/
  );

  try { fs.unlinkSync(tmpFile); } catch {}
});

test('RemoteAuthManager: revoking single device, changing mode, or revoking all', () => {
  const tmpFile = path.join(os.tmpdir(), `pi_test_dev_${Date.now()}_${Math.random()}.json`);
  const auth = new RemoteAuthManager(tmpFile);

  const p1 = auth.generatePairing(60000);
  const dev1 = auth.pair(p1.secret, 'Android Phone', '10.2.0.1', 'view');

  const p2 = auth.generatePairing(60000);
  const dev2 = auth.pair(p2.secret, 'Windows Chrome', '10.2.0.2', 'control');

  assert.strictEqual(auth.getPairedDevices().length, 2);
  assert.strictEqual(auth.getDevice(dev1.deviceId)?.mode, 'view');
  assert.strictEqual(auth.getDevice(dev2.deviceId)?.mode, 'control');

  // Change mode of dev1 to control
  auth.setDeviceMode(dev1.deviceId, 'control');
  assert.strictEqual(auth.getDevice(dev1.deviceId)?.mode, 'control');

  // Revoke dev1
  const removed = auth.revokeDevice(dev1.deviceId);
  assert.strictEqual(removed, true);
  assert.strictEqual(auth.verifyDeviceToken(dev1.deviceToken), null);
  assert.ok(auth.verifyDeviceToken(dev2.deviceToken) !== null);

  // Revoke all
  auth.revokeAll();
  assert.strictEqual(auth.getPairedDevices().length, 0);
  assert.strictEqual(auth.verifyDeviceToken(dev2.deviceToken), null);

  try { fs.unlinkSync(tmpFile); } catch {}
});

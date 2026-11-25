// Pi reports a session's model either as an object or as a bare model id. The
// protocol types the snapshot model as an object, so a bare id must reach the
// app as { id } rather than as a string the app cannot read.
import test from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Session } from '../Session.js';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-snapshot-model-'));
const previousHome = process.env.PI_FRAME_HOME;
process.env.PI_FRAME_HOME = root;
test.after(() => {
  if (previousHome === undefined) delete process.env.PI_FRAME_HOME;
  else process.env.PI_FRAME_HOME = previousHome;
  fs.rmSync(root, { recursive: true, force: true });
});

test('a bare model id is normalised to { id } in the snapshot', () => {
  const session = new Session({ id: 's_bare_model', cwd: root });
  session.model = 'gpt-6-luna';
  assert.deepEqual(session.getSnapshot().runtime.model, { id: 'gpt-6-luna' });
});

test('a model object is passed through to the snapshot unchanged', () => {
  const session = new Session({ id: 's_object_model', cwd: root });
  session.model = { provider: 'openai', id: 'gpt-6-luna', name: 'GPT 6 Luna' };
  assert.deepEqual(session.getSnapshot().runtime.model, { provider: 'openai', id: 'gpt-6-luna', name: 'GPT 6 Luna' });
});

test('a session without a model has a null snapshot model', () => {
  const session = new Session({ id: 's_no_model', cwd: root });
  assert.equal(session.getSnapshot().runtime.model, null);
});

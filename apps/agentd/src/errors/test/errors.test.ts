import test from 'node:test';
import * as assert from 'node:assert/strict';
import { createCodedError, errorCode, errorMessage } from '../errors.js';

test('errorCode reads the code of an object and is undefined otherwise', () => {
  assert.equal(errorCode(createCodedError('boom', 'SESSION_NOT_FOUND')), 'SESSION_NOT_FOUND');
  assert.equal(errorCode(new Error('plain')), undefined);
  assert.equal(errorCode('a string'), undefined);
  assert.equal(errorCode(null), undefined);
  assert.equal(errorCode(undefined), undefined);
});

test('errorMessage returns a string message only', () => {
  assert.equal(errorMessage(new Error('boom')), 'boom');
  assert.equal(errorMessage({ message: 42 }), undefined);
  assert.equal(errorMessage('boom'), undefined);
  assert.equal(errorMessage(null), undefined);
});

test('createCodedError sets the code only when given one', () => {
  const coded = createCodedError('boom', 'CONFIG_INVALID');
  assert.equal(coded.message, 'boom');
  assert.equal(coded.code, 'CONFIG_INVALID');
  assert.equal('code' in createCodedError('plain'), false);
});

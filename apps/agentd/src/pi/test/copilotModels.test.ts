import test from 'node:test';
import * as assert from 'node:assert/strict';
import { createCopilotEntitlementService } from '../copilotModels.js';

const auth = (access = 'tid=test;proxy-ep=proxy.individual.githubcopilot.com', expires = Date.now() + 60_000) => ({
  'github-copilot': { type: 'oauth', refresh: 'refresh-secret', access, expires }
});
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { 'content-type': 'application/json' }
});
const catalog = (models: unknown[]) => ({ data: models });

test('filters Copilot models by picker, policy, and tool support', async () => {
  const service = createCopilotEntitlementService({
    readAuth: () => auth(),
    fetch: async () => json(catalog([
      { id: 'picker-enabled', model_picker_enabled: true, policy: { state: 'enabled' } },
      { id: 'included-no-policy', model_picker_enabled: true },
      { id: 'picker-unconfigured', model_picker_enabled: true, policy: { state: 'unconfigured' } },
      { id: 'picker-disabled', model_picker_enabled: true, policy: { state: 'disabled' } },
      { id: 'not-in-picker', model_picker_enabled: false, policy: { state: 'enabled' } },
      { id: 'no-tools', model_picker_enabled: true, policy: { state: 'enabled' }, capabilities: { supports: { tool_calls: false } } },
      { id: 'tools-false', model_picker_enabled: true, policy: { state: 'enabled' }, tools: false }
    ]))
  });
  const result = await service.get();
  assert.deepEqual([...result.allowedModelIds], ['picker-enabled', 'included-no-policy']);
  assert.deepEqual(result.diagnostic, { available: true });
});

test('uses enabled-policy fallback for individual only when picker has no regular IDs', async () => {
  const service = createCopilotEntitlementService({
    readAuth: () => auth(),
    fetch: async () => json(catalog([
      { id: 'enabled', model_picker_enabled: false, policy: { state: 'enabled' } },
      { id: 'unconfigured', model_picker_enabled: false, policy: { state: 'unconfigured' } },
      { id: 'disabled', model_picker_enabled: true, policy: { state: 'disabled' } }
    ]))
  });
  assert.deepEqual([...(await service.get()).allowedModelIds], ['enabled']);

  const enterprise = createCopilotEntitlementService({
    readAuth: () => auth('tid=test;proxy-ep=proxy.business.githubcopilot.com'),
    fetch: async () => json(catalog([{ id: 'enterprise-enabled', model_picker_enabled: false, policy: { state: 'enabled' } }]))
  });
  assert.deepEqual([...(await enterprise.get()).allowedModelIds], []);
});

test('refreshes expired access token with installed Pi headers and never persists credentials', async () => {
  const credential = auth('expired', 0);
  const before = structuredClone(credential);
  const requests: Array<{ url: string; init?: RequestInit }> = [];
  const service = createCopilotEntitlementService({
    readAuth: () => credential,
    now: () => 100,
    fetch: async (input, init) => {
      const url = String(input);
      requests.push({ url, init });
      if (url.includes('/copilot_internal/v2/token')) {
        return json({ token: 'tid=refreshed;proxy-ep=proxy.individual.githubcopilot.com', expires_at: 999 });
      }
      return json(catalog([{ id: 'allowed', model_picker_enabled: true, policy: { state: 'enabled' } }]));
    }
  });
  const result = await service.get();
  assert.deepEqual([...result.allowedModelIds], ['allowed']);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].url, 'https://api.github.com/copilot_internal/v2/token');
  const refreshHeaders = new Headers(requests[0].init?.headers);
  assert.equal(refreshHeaders.get('authorization'), 'Bearer refresh-secret');
  assert.equal(refreshHeaders.get('user-agent'), 'GitHubCopilotChat/0.35.0');
  const modelHeaders = new Headers(requests[1].init?.headers);
  assert.equal(modelHeaders.get('authorization'), 'Bearer tid=refreshed;proxy-ep=proxy.individual.githubcopilot.com');
  assert.equal(modelHeaders.get('x-github-api-version'), '2026-06-01');
  assert.ok(requests.every((request) => request.init?.signal instanceof AbortSignal));
  assert.deepEqual(credential, before);
});

test('rejects an untrusted proxy endpoint without sending the token to it', async () => {
  const urls: string[] = [];
  const service = createCopilotEntitlementService({
    readAuth: () => auth('tid=secret;proxy-ep=attacker.example'),
    fetch: async (input) => {
      urls.push(String(input));
      return json(catalog([]));
    }
  });
  const result = await service.get();
  assert.deepEqual(urls, []);
  assert.deepEqual([...result.allowedModelIds], []);
  assert.deepEqual(result.diagnostic, {
    available: false,
    code: 'UNTRUSTED_ENDPOINT',
    message: 'GitHub Copilot returned an untrusted model endpoint.'
  });
});

test('does not cache failures and caches successful policy briefly by auth identity', async () => {
  let now = 0;
  let calls = 0;
  let currentAuth = auth();
  const service = createCopilotEntitlementService({
    readAuth: () => currentAuth,
    now: () => now,
    cacheTtlMs: 1_000,
    fetch: async () => {
      calls++;
      if (calls === 1) return json({ message: 'failure body must not be exposed' }, 503);
      return json(catalog([{ id: `model-${calls}`, model_picker_enabled: true, policy: { state: 'enabled' } }]));
    }
  });
  assert.equal((await service.get()).diagnostic.available, false);
  assert.equal((await service.get()).diagnostic.available, true);
  assert.equal(calls, 2);
  assert.equal((await service.get()).allowedModelIds.has('model-2'), true);
  assert.equal(calls, 2);
  now = 1_001;
  assert.equal((await service.get()).allowedModelIds.has('model-3'), true);
  assert.equal(calls, 3);
  currentAuth = auth('tid=other;proxy-ep=proxy.individual.githubcopilot.com');
  await service.get();
  assert.equal(calls, 4);
});

test('bounds response size and reports a safe diagnostic', async () => {
  const body = JSON.stringify(catalog([])) + ' '.repeat(1_048_577);
  const service = createCopilotEntitlementService({
    readAuth: () => auth(),
    fetch: async () => new Response(body)
  });
  const result = await service.get();
  assert.equal(result.diagnostic.available, false);
  if (!result.diagnostic.available) assert.equal(result.diagnostic.code, 'RESPONSE_TOO_LARGE');
});

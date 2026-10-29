import test from 'node:test';
import * as assert from 'node:assert/strict';
import { contextLimitExtension } from '../contextLimitExtension.js';
import { adaptPiEvent } from '../PiEventAdapter.js';

test('PiFrame auth commands use Pi auth runtime, mask secret prompts, and never return credentials', async () => {
  const commands = new Map<string, any>();
  const notices: string[] = [];
  const calls: any[] = [];
  const labels: string[] = [];
  const credentials = [{ providerId: 'anthropic', type: 'api_key' }];
  const runtime = {
    getProviders: () => [
      { id: 'anthropic', name: 'Anthropic', auth: { apiKey: { login: async () => ({}) } } },
      { id: 'oauth-only', name: 'OAuth only', auth: { oauth: { login: async () => ({}) } } },
    ],
    login: async (providerId: string, type: string, interaction: any, options: any) => {
      calls.push({ providerId, type, deviceId: options.getDeviceId(), agentName: options.agentName });
      const secret = await interaction.prompt({ type: 'secret', message: 'API key', placeholder: 'sk-' });
      const selection = await interaction.prompt({
        type: 'select',
        message: 'Account',
        options: [{ id: 'personal', label: 'Work' }, { id: 'team', label: 'Work' }],
      });
      assert.equal(secret, 'secret-value');
      assert.equal(selection, 'team');
      interaction.notify({ type: 'info', message: 'Continue in browser', links: [{ url: 'https://example.test' }] });
      return { type: 'api_key', key: secret };
    },
    listCredentials: async () => credentials,
    getProvider: (id: string) => ({ id, name: 'Anthropic' }),
    logout: async (id: string) => calls.push({ logout: id }),
  };
  const ctx = {
    modelRegistry: { runtime },
    ui: {
      select: async (_title: string, options: string[]) => {
        labels.push(...options);
        if (_title === 'piframe-local:Sign in to a Pi provider') return options[0];
        return options.at(-1);
      },
      input: async (_title: string, placeholder: string) => {
        assert.equal(placeholder, 'piframe-secret:sk-');
        return 'secret-value';
      },
      notify: (message: string) => notices.push(message),
    },
  };
  contextLimitExtension({ registerCommand: (name: string, definition: any) => commands.set(name, definition), on() {}, getSettings: () => ({}) });

  const loginResult = await commands.get('piframe-auth-login').handler('{"deviceId":"123e4567-e89b-12d3-a456-426614174000"}', ctx);
  assert.equal(loginResult, undefined);
  assert.deepEqual(calls[0], {
    providerId: 'anthropic',
    type: 'api_key',
    deviceId: '123e4567-e89b-12d3-a456-426614174000',
    agentName: 'PiFrame',
  });
  assert.ok(labels.includes('OAuth only (oauth-only) — OAuth'));
  assert.ok(labels.includes('Work (2)'));
  assert.equal(notices.some((message) => message.includes('secret-value')), false);
  assert.ok(notices.some((message) => message.includes('https://example.test')));

  await commands.get('piframe-auth-logout').handler('', ctx);
  assert.deepEqual(calls.at(-1), { logout: 'anthropic' });
  assert.ok(notices.includes('Signed out of anthropic.'));
});

test('auth secret UI requests are local-only; normal extension input stays shareable', () => {
  const secret = adaptPiEvent({
    type: 'extension_ui_request', id: 'secret', method: 'input', title: 'piframe-local:API key', placeholder: 'piframe-secret:API key',
  } as any, { sessionId: 's' });
  const normal = adaptPiEvent({
    type: 'extension_ui_request', id: 'normal', method: 'input', placeholder: 'Project name',
  } as any, { sessionId: 's' });

  assert.equal(secret[0].payload.localOnly, true);
  assert.equal(secret[0].payload.title, 'API key');
  const authSelector = adaptPiEvent({
    type: 'extension_ui_request', id: 'selector', method: 'select', title: 'piframe-local:Choose provider', options: ['A'],
  } as any, { sessionId: 's' });
  assert.equal(authSelector[0].payload.localOnly, true);
  assert.equal(authSelector[0].payload.title, 'Choose provider');
  assert.equal(normal[0].payload.localOnly, false);
});

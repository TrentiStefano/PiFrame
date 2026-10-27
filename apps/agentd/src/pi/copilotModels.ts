import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const COPILOT_HEADERS = {
  'User-Agent': 'GitHubCopilotChat/0.35.0',
  'Editor-Version': 'vscode/1.107.0',
  'Editor-Plugin-Version': 'copilot-chat/0.35.0',
  'Copilot-Integration-Id': 'vscode-chat'
};
const COPILOT_API_VERSION = '2026-06-01';
const REQUEST_TIMEOUT_MS = 5_000;
const RESPONSE_LIMIT_BYTES = 1_048_576;
const CACHE_TTL_MS = 30_000;

type RecordValue = Record<string, unknown>;
type CopilotDiagnostic = { available: true } | { available: false; code: string; message: string };
type CopilotResult = { allowedModelIds: Set<string>; diagnostic: CopilotDiagnostic };

type ServiceOptions = {
  readAuth?: () => unknown;
  fetch?: typeof fetch;
  now?: () => number;
  cacheTtlMs?: number;
};

function isRecord(value: unknown): value is RecordValue {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readAuthFile(): unknown {
  const agentDir = process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), '.pi', 'agent');
  try {
    return JSON.parse(fs.readFileSync(path.join(agentDir, 'auth.json'), 'utf8'));
  } catch {
    return undefined;
  }
}

function authFingerprint(refresh: string, access: string, expires: unknown): string {
  return crypto.createHash('sha256').update(JSON.stringify([refresh, access, expires])).digest('hex');
}

function trustedModelsUrl(token: string): { url: string; individual: boolean } {
  const proxy = token.split(';').map((part) => part.trim()).find((part) => part.startsWith('proxy-ep='))?.slice('proxy-ep='.length);
  if (!proxy || !/^proxy\.(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+githubcopilot\.com$/i.test(proxy)) {
    throw new Error('UNTRUSTED_ENDPOINT');
  }
  const host = `api.${proxy.slice('proxy.'.length).toLowerCase()}`;
  const url = new URL('/models', `https://${host}`);
  if (url.protocol !== 'https:' || url.hostname !== host || url.port) throw new Error('UNTRUSTED_ENDPOINT');
  return { url: url.href, individual: host === 'api.individual.githubcopilot.com' };
}

async function readJsonBounded(response: Response): Promise<unknown> {
  const contentLength = Number(response.headers.get('content-length'));
  if (Number.isFinite(contentLength) && contentLength > RESPONSE_LIMIT_BYTES) throw new Error('RESPONSE_TOO_LARGE');

  const reader = response.body?.getReader();
  if (!reader) {
    const text = await response.text();
    if (Buffer.byteLength(text) > RESPONSE_LIMIT_BYTES) throw new Error('RESPONSE_TOO_LARGE');
    return JSON.parse(text);
  }

  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > RESPONSE_LIMIT_BYTES) {
        await reader.cancel();
        throw new Error('RESPONSE_TOO_LARGE');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function parseAllowedModelIds(raw: unknown, individual: boolean): Set<string> {
  if (!isRecord(raw) || !Array.isArray(raw.data)) throw new Error('INVALID_MODEL_CATALOG');
  const items = raw.data;
  if (items.length > 10_000) throw new Error('INVALID_MODEL_CATALOG');

  const models = items.flatMap((item) => {
    if (!isRecord(item) || typeof item.id !== 'string' || item.id.length === 0 || item.id.length > 256) return [];
    const capabilities = isRecord(item.capabilities) ? item.capabilities : undefined;
    const supports = capabilities && isRecord(capabilities.supports) ? capabilities.supports : undefined;
    if (item.tools === false || supports?.tool_calls === false) return [];
    return [{ id: item.id, picker: item.model_picker_enabled === true, state: isRecord(item.policy) ? item.policy.state : undefined }];
  });
  // Models without a policy (for example included Codex models) need no opt-in.
  const regular = models.filter((model) => model.picker && (model.state === undefined || model.state === 'enabled'));
  const selected = regular.length > 0 || !individual
    ? regular
    : models.filter((model) => model.state === 'enabled');
  return new Set(selected.map((model) => model.id));
}

function failure(code: string, message: string): CopilotResult {
  return { allowedModelIds: new Set(), diagnostic: { available: false, code, message } };
}

export function createCopilotEntitlementService(options: ServiceOptions = {}) {
  const fetchImpl = options.fetch ?? globalThis.fetch;
  const now = options.now ?? Date.now;
  const cacheTtlMs = options.cacheTtlMs ?? CACHE_TTL_MS;
  const cache = new Map<string, { expiresAt: number; allowedModelIds: string[] }>();

  return {
    async get(): Promise<CopilotResult> {
      let auth: unknown;
      try {
        auth = options.readAuth ? options.readAuth() : readAuthFile();
      } catch {
        return failure('NO_CREDENTIALS', 'GitHub Copilot credentials are unavailable.');
      }
      const entry = isRecord(auth) && isRecord(auth['github-copilot']) ? auth['github-copilot'] : undefined;
      if (!entry || entry.type !== 'oauth' || typeof entry.refresh !== 'string' || entry.refresh.length === 0 || entry.refresh.length > 8192 ||
          typeof entry.access !== 'string' || entry.access.length === 0 || entry.access.length > 8192 ||
          /[\r\n]/.test(entry.refresh) || /[\r\n]/.test(entry.access)) {
        return failure('NO_CREDENTIALS', 'GitHub Copilot credentials are unavailable.');
      }

      const fingerprint = authFingerprint(entry.refresh, entry.access, entry.expires);
      const cached = cache.get(fingerprint);
      if (cached && cached.expiresAt > now()) {
        return { allowedModelIds: new Set(cached.allowedModelIds), diagnostic: { available: true } };
      }

      try {
        let token = entry.access;
        if (typeof entry.expires !== 'number' || entry.expires <= now()) {
          const response = await fetchImpl('https://api.github.com/copilot_internal/v2/token', {
            headers: { Accept: 'application/json', Authorization: `Bearer ${entry.refresh}`, ...COPILOT_HEADERS },
            redirect: 'error',
            signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
          });
          if (!response.ok) throw new Error('TOKEN_REFRESH_FAILED');
          const refreshed = await readJsonBounded(response);
          if (!isRecord(refreshed) || typeof refreshed.token !== 'string' || typeof refreshed.expires_at !== 'number') {
            throw new Error('TOKEN_REFRESH_FAILED');
          }
          token = refreshed.token;
        }

        const endpoint = trustedModelsUrl(token);
        const response = await fetchImpl(endpoint.url, {
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${token}`,
            ...COPILOT_HEADERS,
            'X-GitHub-Api-Version': COPILOT_API_VERSION
          },
          redirect: 'error',
          signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
        });
        if (!response.ok) throw new Error('MODEL_CATALOG_FAILED');
        const allowedModelIds = parseAllowedModelIds(await readJsonBounded(response), endpoint.individual);
        cache.set(fingerprint, { expiresAt: now() + cacheTtlMs, allowedModelIds: [...allowedModelIds] });
        if (cache.size > 8) cache.delete(cache.keys().next().value!);
        return { allowedModelIds, diagnostic: { available: true } };
      } catch (error) {
        const code = error instanceof Error ? error.message : '';
        if (code === 'UNTRUSTED_ENDPOINT') return failure(code, 'GitHub Copilot returned an untrusted model endpoint.');
        if (code === 'RESPONSE_TOO_LARGE') return failure(code, 'GitHub Copilot returned an oversized response.');
        if (code === 'INVALID_MODEL_CATALOG') return failure(code, 'GitHub Copilot returned an invalid model catalog.');
        if (code === 'TOKEN_REFRESH_FAILED') return failure(code, 'GitHub Copilot token refresh failed.');
        return failure('MODEL_CATALOG_FAILED', 'GitHub Copilot model policy could not be verified.');
      }
    }
  };
}

const copilotEntitlements = createCopilotEntitlementService();

export async function getCopilotEntitlements(): Promise<CopilotResult> {
  return copilotEntitlements.get();
}

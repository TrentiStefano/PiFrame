import type * as http from 'node:http';

export function isLoopbackHost(host: string | undefined, port: number): boolean {
  if (!host) return false;
  try {
    const url = new URL(`http://${host}`);
    return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) &&
      !url.username && !url.password && url.pathname === '/' &&
      Number(url.port || 80) === port;
  } catch { return false; }
}

const PROXY_HEADER_NAMES = [
  'x-forwarded-for',
  'x-forwarded-proto',
  'x-forwarded-host',
  'x-forwarded-port',
  'x-forwarded-server',
  'x-real-ip',
  'forwarded',
  'via',
  'cf-connecting-ip',
  'cf-ray',
  'cf-visitor',
  'cf-ipcountry',
  'true-client-ip'
];

/**
 * Checks whether an incoming HTTP request carries reverse-proxy headers.
 * The direct loopback listener strictly rejects these to prevent reverse-proxy confusion.
 */
export function hasProxyHeaders(req: http.IncomingMessage | { headers: Record<string, string | string[] | undefined> }): boolean {
  const headers = req.headers;
  for (const name of PROXY_HEADER_NAMES) {
    if (headers[name] !== undefined) return true;
  }
  return false;
}

export function isOriginAllowed(origin: string | undefined, allowedOrigins: string[], port: number): boolean {
  // Desktop clients (like Flutter Desktop) don't send Origin
  if (!origin) return true;

  try {
    const parsed = new URL(origin);
    const host = parsed.hostname;

    // Loopback origins are allowed on matching port
    if (host === '127.0.0.1' || host === 'localhost') {
      const originPort = parsed.port ? parseInt(parsed.port, 10) : (parsed.protocol === 'https:' ? 443 : 80);
      if (originPort === port) return true;
    }

    // Check against custom configured origins
    for (const allowed of allowedOrigins) {
      if (allowed === origin || allowed === `${parsed.protocol}//${parsed.host}`) {
        return true;
      }
    }
  } catch {
    return false;
  }

  return false;
}

export function isHostAllowed(
  host: string | undefined,
  port: number,
  remoteManager?: { isRemoteHostAllowed: (h: string | undefined) => boolean }
): boolean {
  if (isLoopbackHost(host, port)) return true;
  if (remoteManager && remoteManager.isRemoteHostAllowed(host)) return true;
  return false;
}

export function isOriginOrRemoteAllowed(
  origin: string | undefined,
  allowedOrigins: string[],
  port: number,
  remoteManager?: { isRemoteOriginAllowed: (o: string | undefined) => boolean }
): boolean {
  if (isOriginAllowed(origin, allowedOrigins, port)) return true;
  if (remoteManager && remoteManager.isRemoteOriginAllowed(origin)) return true;
  return false;
}

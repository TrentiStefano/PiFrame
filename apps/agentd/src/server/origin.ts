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

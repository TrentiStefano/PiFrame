#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';

const args = process.argv.slice(2);
const agentDir = path.resolve(process.env.PI_CODING_AGENT_DIR || path.join(process.env.HOME || process.env.USERPROFILE || process.cwd(), '.pi', 'agent'));
const packagesPath = path.join(agentDir, 'fake-packages.json');

function packageName(spec: string): string {
  const value = spec.startsWith('npm:') ? spec.slice(4) : spec;
  const slash = value.lastIndexOf('/');
  const at = value.lastIndexOf('@');
  return at > slash ? value.slice(0, at) : value;
}

function requestedVersion(spec: string): string | null {
  const value = spec.startsWith('npm:') ? spec.slice(4) : spec;
  const slash = value.lastIndexOf('/');
  const at = value.lastIndexOf('@');
  return at > slash ? value.slice(at + 1) : null;
}

function main(): void {
  if (args[0] === 'view' && args[1] && args[2] === 'version' && args.includes('--json')) {
    try {
      const packages = JSON.parse(fs.readFileSync(packagesPath, 'utf8')) as Array<{ source?: string; latest?: string }>;
      const name = packageName(args[1]);
      const item = packages.find((entry) => entry.source?.startsWith('npm:') && packageName(entry.source) === name);
      const requested = requestedVersion(args[1]);
      const version = (requested && requested !== 'latest' && requested !== '*') || item?.latest || item?.source?.split('@').at(-1) || '1.0.0';
      console.log(JSON.stringify(version));
      return;
    } catch {
      console.log(JSON.stringify(requestedVersion(args[1]) || '1.0.0'));
      return;
    }
  }
  console.log('{}');
}

main();

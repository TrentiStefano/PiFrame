import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const bundlePath = path.join(root, 'apps/agentd/dist/pi-agentd.cjs');
const bundle = await readFile(bundlePath, 'utf8');
const requiredCommands = [
  'workspace.listFiles',
  'workspace.readFile',
  'workspace.saveFile',
  'workspace.gitAction',
  'scanFastSnapshot',
];
const missing = requiredCommands.filter((command) => !bundle.includes(command));
if (missing.length) {
  throw new Error(`Stale agentd bundle at ${bundlePath}; missing commands: ${missing.join(', ')}. Run pnpm run build:agentd.`);
}
console.log(`OK: packaged agentd supports ${requiredCommands.join(', ')}`);

import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('Strict D16 Telemetry Ban: No remote analytics or external network calls in apps/agentd/src', () => {
  const srcDir = path.resolve(__dirname, '..');
  assert.ok(fs.existsSync(srcDir), 'src directory must exist');

  const tsFiles: string[] = [];
  function scan(dir: string) {
    const entries = fs.readdirSync(dir);
    for (const e of entries) {
      const full = path.join(dir, e);
      if (fs.statSync(full).isDirectory()) {
        scan(full);
      } else if (full.endsWith('.ts') && !full.endsWith('.test.ts')) {
        tsFiles.push(full);
      }
    }
  }

  scan(srcDir);

  const violations: string[] = [];
  const bannedKeywords = [
    'sentry',
    'mixpanel',
    'amplitude',
    'posthog',
    'google-analytics',
    'segment',
    'telemetry.piframe'
  ];

  // Regex matching external URLs other than 127.0.0.1, localhost, or standard schemas
  const remoteUrlRegex = /https?:\/\/(?!127\.0\.0\.1|localhost|json-schema\.org)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

  for (const file of tsFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const lines = content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      for (const kw of bannedKeywords) {
        if (line.toLowerCase().includes(kw)) {
          violations.push(`${file}:${i + 1}: Found banned keyword "${kw}": ${line}`);
        }
      }

      const match = line.match(remoteUrlRegex);
      if (match) {
        violations.push(`${file}:${i + 1}: Found remote external URL "${match.join(', ')}": ${line}`);
      }
    }
  }

  assert.strictEqual(
    violations.length,
    0,
    `D16 strictly prohibits any remote telemetry or external network calls. Violations found:\n${violations.join('\n')}`
  );
});

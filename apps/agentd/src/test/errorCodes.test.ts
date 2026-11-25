// Every error code the daemon can put on the wire must be a member of the protocol's
// error-code enum, so clients can rely on the list and the daemon never needs a cast to send it.
import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PCP_ERROR_CODES } from '@piframe/pcp-ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Compiled to dist/test, so the sources sit two levels up and the repository root four.
const srcDir = path.resolve(__dirname, '../../src');
const schemaFile = path.resolve(__dirname, '../../../../packages/pcp-spec/schema/error.schema.json');

// Daemon error codes are SCREAMING_SNAKE with at least one underscore. Node and OS codes
// (ENOENT, EPERM) are single-word and are compared, never emitted, so they are not matched.
const codeLiteral = /'([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)'/g;

function sourceFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(dir)) {
    const full = path.join(dir, entry);
    if (fs.statSync(full).isDirectory()) files.push(...sourceFiles(full));
    else if (full.endsWith('.ts') && !full.endsWith('.test.ts')) files.push(full);
  }
  return files;
}

function schemaCodes(): string[] {
  const schema = JSON.parse(fs.readFileSync(schemaFile, 'utf8')) as {
    properties: { payload: { properties: { code: { enum: string[] } } } };
  };
  return schema.properties.payload.properties.code.enum;
}

test('every error code literal in the daemon source is in the protocol error-code enum', () => {
  assert.ok(fs.existsSync(srcDir), 'daemon src directory must exist');
  const allowed = new Set(schemaCodes());
  const unlisted = new Map<string, string[]>();

  for (const file of sourceFiles(srcDir)) {
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, index) => {
      for (const match of line.matchAll(codeLiteral)) {
        const code = match[1]!;
        if (allowed.has(code)) continue;
        const where = `${path.relative(srcDir, file)}:${index + 1}`;
        unlisted.set(code, [...(unlisted.get(code) ?? []), where]);
      }
    });
  }

  const report = [...unlisted].map(([code, places]) => `${code} at ${places.join(', ')}`);
  assert.deepEqual(report, [], `Daemon emits error codes missing from packages/pcp-spec/schema/error.schema.json`);
});

test('the TypeScript error-code list matches the protocol error-code enum', () => {
  assert.deepEqual([...PCP_ERROR_CODES].sort(), [...schemaCodes()].sort());
});

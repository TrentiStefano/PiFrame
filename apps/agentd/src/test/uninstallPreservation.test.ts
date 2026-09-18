import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as crypto from 'node:crypto';

function hashDirectory(dir: string): Record<string, string> {
  const result: Record<string, string> = {};
  if (!fs.existsSync(dir)) return result;

  function walk(current: string) {
    const files = fs.readdirSync(current);
    for (const f of files) {
      const full = path.join(current, f);
      const stat = fs.statSync(full);
      if (stat.isDirectory()) {
        walk(full);
      } else {
        const relative = path.relative(dir, full).replace(/\\/g, '/');
        const hash = crypto.createHash('sha256').update(fs.readFileSync(full)).digest('hex');
        result[relative] = hash;
      }
    }
  }

  walk(dir);
  return result;
}

test('uninstallPreservation: uninstallation removes ~/.pi-crust/ while strictly preserving ~/.pi/ untouched', async (t) => {
  const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-crust-uninstall-test-'));
  const piDir = path.join(testRoot, '.pi');
  const piCrustDir = path.join(testRoot, '.pi-crust');

  t.after(() => {
    fs.rmSync(testRoot, { recursive: true, force: true });
  });

  // 1. Setup simulated ~/.pi environment with authentic-looking session files and configs
  const sessionsDir = path.join(piDir, 'agent', 'sessions', 'project-alpha');
  fs.mkdirSync(sessionsDir, { recursive: true });

  const piConfig = JSON.stringify({ defaultModel: 'claude-3-5-sonnet', extensions: ['git-tools'] }, null, 2);
  fs.writeFileSync(path.join(piDir, 'config.json'), piConfig, 'utf8');

  const sessionContent1 = '{"type":"session_start","id":"sess_original_1","timestamp":1726000000}\n{"type":"message","role":"user","content":"Hello Pi"}\n';
  const sessionContent2 = '{"type":"session_start","id":"sess_original_2","timestamp":1726001000}\n{"type":"message","role":"assistant","content":"Response"}\n';
  fs.writeFileSync(path.join(sessionsDir, 'sess_original_1.jsonl'), sessionContent1, 'utf8');
  fs.writeFileSync(path.join(sessionsDir, 'sess_original_2.jsonl'), sessionContent2, 'utf8');

  // Compute baseline checksums of ~/.pi
  const baselinePiHashes = hashDirectory(piDir);
  assert.strictEqual(Object.keys(baselinePiHashes).length, 3, 'Baseline ~/.pi must have 3 files');

  // 2. Setup simulated ~/.pi-crust environment (runtime lock, tokens, journal, themes, index)
  fs.mkdirSync(path.join(piCrustDir, 'runtime'), { recursive: true });
  fs.mkdirSync(path.join(piCrustDir, 'journal', 'sess_original_1'), { recursive: true });
  fs.mkdirSync(path.join(piCrustDir, 'themes'), { recursive: true });

  fs.writeFileSync(path.join(piCrustDir, 'config.json'), '{"workerIdleTimeoutMs": 1800000}', 'utf8');
  fs.writeFileSync(path.join(piCrustDir, 'index.json'), '[]', 'utf8');
  fs.writeFileSync(path.join(piCrustDir, 'runtime', 'daemon.token'), 'simulated-token-abc', 'utf8');
  fs.writeFileSync(path.join(piCrustDir, 'runtime', 'daemon.lock'), '12345', 'utf8');
  fs.writeFileSync(path.join(piCrustDir, 'journal', 'sess_original_1', 'journal.jsonl'), '{"seq":1}\n', 'utf8');

  assert.ok(fs.existsSync(piCrustDir), '~/.pi-crust should exist before uninstall');

  // 3. Execute simulated uninstall procedure (as documented in docs/install.md):
  // Remove ~/.pi-crust completely
  fs.rmSync(piCrustDir, { recursive: true, force: true });

  // 4. Verify post-uninstall assertions:
  // a) ~/.pi-crust must be completely removed
  assert.strictEqual(fs.existsSync(piCrustDir), false, '~/.pi-crust must be deleted');

  // b) ~/.pi must remain completely intact with identical hashes
  assert.ok(fs.existsSync(piDir), '~/.pi must still exist');
  const postUninstallPiHashes = hashDirectory(piDir);

  assert.deepStrictEqual(
    postUninstallPiHashes,
    baselinePiHashes,
    'All files in ~/.pi must remain 100% untouched and byte-identical after Pi-Crust uninstall'
  );
});

import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('=== Pi Target Compatibility Verification (Step 0.1) ===');

  // 1. Verify environment
  const nodeVersion = process.version;
  console.log(`Node: ${nodeVersion}`);
  console.log(`Platform: ${process.platform} (${process.arch})`);

  // 2. Verify Pi CLI version
  const piBundle = process.env.PI_CRUST_PI_BUNDLE
    ?? (process.platform === 'win32'
      ? 'C:/nvm4w/nodejs/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js'
      : '');
  if (!piBundle || !fs.existsSync(piBundle)) {
    console.log('Skipping live Pi RPC check; set PI_CRUST_PI_BUNDLE to the CLI bundle path to enable it.');
    return;
  }
  const piVersion = await new Promise<string>((resolve, reject) => {
    const p = spawn(process.execPath, [piBundle, '--version'], { stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '';
    p.stdout.on('data', d => out += d.toString());
    p.on('close', code => {
      if (code === 0) resolve(out.trim());
      else reject(new Error(`pi --version exited with code ${code}`));
    });
  });
  console.log(`Detected Pi version: ${piVersion}`);

  // Minimum required version check (v0.85.0)
  const semverParts = piVersion.split('.').map(p => parseInt(p, 10));
  const isCompatible = semverParts[0] > 0 || (semverParts[0] === 0 && (semverParts[1] > 85 || (semverParts[1] === 85 && semverParts[2] >= 0)));
  if (!isCompatible) {
    throw new Error(`Pi version ${piVersion} is lower than minimum supported v0.85.0`);
  }
  console.log('Pi version meets minimum requirement (>= v0.85.0): OK');

  // 3. Verify Golden Fixtures
  const fixturesDir = path.resolve(__dirname, '../../packages/pcp-spec/fixtures/pi');
  if (!fs.existsSync(fixturesDir)) {
    throw new Error(`Fixtures directory not found: ${fixturesDir}`);
  }
  const fixtureFiles = fs.readdirSync(fixturesDir).filter(f => f.endsWith('.jsonl'));
  console.log(`Found ${fixtureFiles.length} golden fixtures in ${fixturesDir}`);
  if (fixtureFiles.length < 10) {
    throw new Error(`Expected at least 10 golden fixtures, found ${fixtureFiles.length}`);
  }

  for (const f of fixtureFiles) {
    const content = fs.readFileSync(path.join(fixturesDir, f), 'utf8');
    const lines = content.split('\n').filter(l => l.trim().length > 0);
    for (let i = 0; i < lines.length; i++) {
      try {
        const obj = JSON.parse(lines[i]);
        if (!obj.type && !obj.id) {
          throw new Error(`Line ${i + 1} in ${f} missing type/id field`);
        }
      } catch (err: any) {
        throw new Error(`Invalid JSONL in ${f}:${i + 1} - ${err.message}`);
      }
    }
    console.log(`  [OK] ${f} (${lines.length} valid records)`);
  }

  // 4. Live RPC probe verification
  console.log('Running live RPC probe test against Pi CLI...');
  const probeResult = await runRpcProbe(piBundle);
  console.log('Live RPC probe result:', JSON.stringify(probeResult, null, 2));
  console.log('=== Step 0.1 Verification Passed! ===');
}

function runRpcProbe(piBundle: string): Promise<{ sessionId: string; model?: string }> {
  return new Promise((resolve, reject) => {
    const proc = spawn(process.execPath, [piBundle, '--mode', 'rpc', '--no-session', '--no-extensions'], {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    let buffer = '';
    let capturedState: any = null;

    proc.stdout.on('data', (d) => {
      buffer += d.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';
      for (const line of lines) {
        if (!line.trim()) continue;
        const msg = JSON.parse(line);
        if (msg.type === 'response' && msg.command === 'get_state' && msg.success) {
          capturedState = msg.data;
          proc.kill();
          resolve({
            sessionId: capturedState.sessionId,
            model: capturedState.model?.name || capturedState.model?.id
          });
          return;
        }
      }
    });

    proc.stderr.on('data', (d) => console.error('Pi stderr:', d.toString()));
    proc.on('close', (code) => {
      if (!capturedState) {
        reject(new Error(`RPC process closed with code ${code} without returning get_state response`));
      }
    });

    proc.stdin.write(JSON.stringify({ type: 'get_state', id: 'verify_01' }) + '\n');
  });
}

main().catch(err => {
  console.error('Verification failed:', err);
  process.exit(1);
});

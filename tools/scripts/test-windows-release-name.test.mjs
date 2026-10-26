import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const cmake = readFileSync('apps/pi_frame/windows/CMakeLists.txt', 'utf8');
const installer = readFileSync('packaging/windows/PiFrame.iss', 'utf8');
const workflow = readFileSync('.github/workflows/release.yml', 'utf8');
const debPackager = readFileSync('tools/scripts/package-linux-deb.sh', 'utf8');

test('Linux release declares libnotify build and runtime dependencies', () => {
  const aptInstallLines = workflow.match(/^\s*sudo apt-get install -y .*$/gm) ?? [];
  assert.equal(aptInstallLines.length, 2, 'release workflow must have two Linux dependency lists');
  for (const line of aptInstallLines) {
    assert.match(line, /\blibnotify-dev\b/);
  }
  assert.match(debPackager, /^Depends: .*\blibnotify4\b/m);
});

test('Windows executable name matches CMake, installer, and release bundle guard', () => {
  const binaryName = cmake.match(/^set\(BINARY_NAME\s+"([^"]+)"\)/m)?.[1];
  assert.ok(binaryName, 'CMake must define BINARY_NAME');

  const executable = `${binaryName}.exe`;
  assert.match(installer, new RegExp(`\\\\${executable.replace('.', '\\.')}\\b`));
  assert.ok(
    workflow.includes(`Join-Path $bundle '${executable}'`),
    `release workflow must check for ${executable}`,
  );
});

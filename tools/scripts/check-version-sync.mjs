import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = (path) => readFile(path, 'utf8');
const manifest = JSON.parse(await read('.release-please-manifest.json'));
const releaseConfig = JSON.parse(await read('release-please-config.json'));
const packageConfig = releaseConfig.packages['.'];
const version = manifest['.'];
assert.equal(packageConfig['release-type'], 'node');
for (const path of [
  'apps/pi_frame/pubspec.yaml',
  'apps/agentd/package.json',
  'apps/agentd/src/main.ts',
  'apps/pi_frame/lib/app/app_version.dart',
]) {
  assert.ok(
    packageConfig['extra-files'].some((file) => file.path === path),
    `${path} is missing from release-please extra-files`,
  );
}
assert.match(version, /^\d+\.\d+\.\d+$/, 'manifest must contain a SemVer version');

const rootPackage = JSON.parse(await read('package.json'));
const agentPackage = JSON.parse(await read('apps/agentd/package.json'));
const pubspec = await read('apps/pi_frame/pubspec.yaml');
const daemon = await read('apps/agentd/src/main.ts');
const dartVersion = await read('apps/pi_frame/lib/app/app_version.dart');
const pubspecVersion = pubspec.match(/^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$/m)?.[1];
const daemonVersion = daemon.match(/const VERSION = '([^']+)';\s*\/\/ x-release-please-version/)?.[1];
const appVersion = dartVersion.match(/const piFrameVersionDefault = '([^']+)';\s*\/\/ x-release-please-version/)?.[1];

assert.equal(rootPackage.version, version, 'root package.json version is out of sync');
assert.equal(agentPackage.version, version, 'agentd package.json version is out of sync');
assert.equal(pubspecVersion, version, 'Flutter pubspec version is out of sync');
assert.equal(daemonVersion, version, 'daemon source version is out of sync');
assert.equal(appVersion, version, 'Flutter app fallback version is out of sync');
console.log(`Version metadata is synchronized at ${version}`);

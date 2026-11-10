import test, { type TestContext } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import {
  PiPackageService,
  parsePiListOutput,
  pinnedNpmSource,
  pinnedNpmVersion,
} from '../PiPackageService.js';
import { resolveNpmLaunch } from '../executable.js';

async function packageFixture(
  context: TestContext,
  packages: { source: string; version: string; scope?: 'user' | 'project' }[],
) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'piframe-package-updates-'));
  context.after(() => fs.rm(directory, { recursive: true, force: true }));
  const npmCli = path.join(directory, 'node_modules', 'npm', 'bin', 'npm-cli.js');
  await fs.mkdir(path.dirname(npmCli), { recursive: true });
  await fs.writeFile(npmCli, '');
  const piCli = path.join(directory, 'pi.js');
  const calls: string[][] = [];
  const targets = new Map<string, unknown>();
  const incompatible = new Set<string>();
  const installPaths = new Map<string, string>();
  let update: (source: string) => Promise<void> = async () => {};
  let registryError: Error | undefined;
  for (const [index, pkg] of packages.entries()) {
    const installPath = path.join(directory, 'managed', 'node_modules', `package-${index}`);
    installPaths.set(pkg.source, installPath);
    await fs.mkdir(installPath, { recursive: true });
    await fs.writeFile(
      path.join(installPath, 'package.json'),
      JSON.stringify({ name: `package-${index}`, version: pkg.version }),
    );
  }
  const service = new PiPackageService(piCli, async (_file, args, options) => {
    assert.equal(options.env?.npm_config_prefer_online, 'true');
    const command = args.slice(1);
    calls.push(command);
    if (args[0] === npmCli) {
      if (registryError) throw registryError;
      if (command[0] === 'install') {
        assert.ok(command.includes('--dry-run'));
        assert.ok(command.includes('--ignore-scripts'));
        if (incompatible.has(command[1])) {
          throw Object.assign(new Error('Unsupported platform'), {
            stdout: JSON.stringify({
              error: { code: 'EBADPLATFORM', summary: 'Unsupported platform for @nested/required@1.2.0' },
            }),
            stderr: '',
          });
        }
        return { stdout: '{"added":0}', stderr: '' };
      }
      assert.ok(targets.has(command[1]), `Unexpected package spec: ${command[1]}`);
      return { stdout: JSON.stringify(targets.get(command[1])), stderr: '' };
    }
    if (command[0] === 'list') {
      const lines: string[] = [];
      for (const scope of ['user', 'project']) {
        lines.push(scope === 'user' ? 'User packages:' : 'Project packages:');
        for (const pkg of packages.filter((item) => (item.scope ?? 'user') === scope)) {
          lines.push(`  ${pkg.source}`, `    ${installPaths.get(pkg.source)}`);
        }
      }
      return { stdout: lines.join('\n'), stderr: '' };
    }
    if (command[0] === 'update') {
      await update(command[1]);
      return { stdout: 'Update command completed.', stderr: '' };
    }
    throw new Error(`Unexpected command: ${command.join(' ')}`);
  });
  return {
    service, directory, npmCli, piCli, calls, targets, incompatible,
    setUpdate(value: typeof update) { update = value; },
    setRegistryError(value: Error) { registryError = value; },
    async setVersion(source: string, version: string) {
      const installPath = installPaths.get(source);
      assert.ok(installPath);
      await fs.writeFile(path.join(installPath, 'package.json'), JSON.stringify({ version }));
    },
  };
}

test('package list parser returns personal packages and ignores project scope', () => {
  const packages = parsePiListOutput(`User packages:
  npm:pi-caveman
    C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\pi-caveman
  npm:@scope/tools@1.2.3
    C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\@scope\\tools
Project packages:
  ./local-package
    C:\\repo\\local-package
`);
  assert.deepEqual(packages, [
    {
      source: 'npm:pi-caveman',
      installPath: 'C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\pi-caveman',
      scope: 'user',
    },
    {
      source: 'npm:@scope/tools@1.2.3',
      installPath: 'C:\\Users\\user\\.pi\\agent\\npm\\node_modules\\@scope\\tools',
      scope: 'user',
    },
  ]);
  assert.equal(pinnedNpmVersion('npm:@scope/tools@1.2.3'), '1.2.3');
  assert.equal(pinnedNpmVersion('npm:pi-caveman'), null);
});

test('pin creates an exact npm source and rejects invalid specs', () => {
  assert.equal(
    pinnedNpmSource('npm:@scope/tools', 'v2.4.0'),
    'npm:@scope/tools@2.4.0',
  );
  assert.throws(() => pinnedNpmSource('git:github.com/a/b', '2.4.0'));
  assert.throws(() => pinnedNpmSource('npm:tools', 'latest; delete files'));
});

test('update checking follows configured sources, skips pins and excludes project packages', async (context) => {
  const fixture = await packageFixture(context, [
    { source: 'npm:package', version: '0.1.14' },
    { source: 'npm:range-package@^1.0.0', version: '1.0.0' },
    { source: 'npm:tag-package@next', version: '2.0.0-beta.2' },
    { source: 'npm:pinned@1.2.3', version: '1.2.3' },
    { source: 'git:github.com/example/tools', version: '1.0.0' },
    { source: 'npm:project-package', version: '0.1.0', scope: 'project' },
  ]);
  fixture.targets.set('package@latest', '1.2.0');
  fixture.targets.set('range-package@^1.0.0', ['1.9.0', '1.2.0']);
  fixture.targets.set('tag-package@next', '2.0.0-beta.10');
  const packages = await fixture.service.list(true);
  assert.equal(packages.length, 5);
  assert.equal(packages[0].latestVersion, '1.2.0');
  assert.equal(packages[1].latestVersion, '1.9.0');
  assert.equal(packages[2].latestVersion, '2.0.0-beta.10');
  assert.equal(packages[3].latestVersion, undefined);
  assert.equal(packages[4].latestVersion, undefined);
  assert.deepEqual(fixture.calls.filter((args) => args[0] === 'view').sort((a, b) => a[1].localeCompare(b[1])), [
    ['view', 'package@latest', 'version', '--json'],
    ['view', 'range-package@^1.0.0', 'version', '--json'],
    ['view', 'tag-package@next', 'version', '--json'],
  ]);
});

test('npm launch uses the npm entrypoint beside Pi, without a Windows shim or shell', async (context) => {
  const fixture = await packageFixture(context, []);
  const args = ['view', 'package@>=1.0.0 <2.0.0', 'version', '--json'];
  assert.deepEqual(resolveNpmLaunch(fixture.piCli, args), {
    file: process.execPath, args: [fixture.npmCli, ...args],
  });
});

test('update verifies the installed version and preserves the unpinned source', async (context) => {
  const fixture = await packageFixture(context, [{ source: 'npm:package', version: '0.1.14' }]);
  fixture.targets.set('package@latest', '1.2.0');
  fixture.setUpdate((source) => fixture.setVersion(source, '1.2.0'));
  const result = await fixture.service.update('npm:package');
  assert.deepEqual(result, {
    output: 'Update command completed.', status: 'updated', previousVersion: '0.1.14', version: '1.2.0',
  });
  assert.ok(fixture.calls.some((args) => args[0] === 'update' && args[1] === 'npm:package'));
  assert.equal((await fixture.service.list())[0].source, 'npm:package');
});

test('a zero exit code with an unchanged version is rejected', async (context) => {
  const fixture = await packageFixture(context, [{ source: 'npm:package', version: '0.1.14' }]);
  fixture.targets.set('package@latest', '1.2.0');
  await assert.rejects(
    fixture.service.update('npm:package'),
    /installed version 0\.1\.14, expected 1\.2\.0/,
  );
});

test('an update that remains below the available version is rejected', async (context) => {
  const fixture = await packageFixture(context, [{ source: 'npm:package', version: '0.1.14' }]);
  fixture.targets.set('package@latest', '1.2.0');
  fixture.setUpdate((source) => fixture.setVersion(source, '0.1.15'));
  await assert.rejects(
    fixture.service.update('npm:package'),
    /installed version 0\.1\.15, expected 1\.2\.0/,
  );
});

test('current, newer and pinned versions do not run an installation', async (context) => {
  const fixture = await packageFixture(context, [
    { source: 'npm:current', version: '1.2.0' },
    { source: 'npm:newer', version: '2.0.0-beta.10' },
    { source: 'npm:pinned@1.2.3', version: '1.2.3' },
  ]);
  fixture.targets.set('current@latest', '1.2.0');
  fixture.targets.set('newer@latest', '2.0.0-beta.2');
  assert.equal((await fixture.service.update('npm:current')).status, 'current');
  assert.equal((await fixture.service.update('npm:newer')).status, 'current');
  assert.equal((await fixture.service.update('npm:pinned@1.2.3')).status, 'pinned');
  assert.equal(fixture.calls.some((args) => args[0] === 'update'), false);
  assert.equal(fixture.calls.some((args) => args[0] === 'view' && args[1].startsWith('pinned')), false);
});

test('registry failures and invalid versions are not reported as successful checks', async (context) => {
  const fixture = await packageFixture(context, [{ source: 'npm:package', version: '1.0.0' }]);
  fixture.targets.set('package@latest', { error: 'Registry unavailable' });
  await assert.rejects(fixture.service.list(true), /no valid version/);
  fixture.setRegistryError(new Error('Registry connection failed'));
  await assert.rejects(fixture.service.update('npm:package'), /Registry connection failed/);
  assert.equal(fixture.calls.some((args) => args[0] === 'update'), false);
});

test('incompatible required dependencies are exposed and do not run a Pi update', async (context) => {
  const fixture = await packageFixture(context, [{ source: 'npm:package', version: '0.1.14' }]);
  fixture.targets.set('package@latest', '1.2.0');
  fixture.incompatible.add('package@1.2.0');
  const packages = await fixture.service.list(true);
  assert.equal(packages[0].latestVersion, '1.2.0');
  assert.match(packages[0].updateError ?? '', /not installable.*@nested\/required/);
  assert.equal((await fixture.service.list())[0].updateError, packages[0].updateError);
  await assert.rejects(fixture.service.update('npm:package'), /not installable/);
  assert.equal(fixture.calls.some((args) => args[0] === 'update'), false);
  assert.equal((await fixture.service.list())[0].version, '0.1.14');
});

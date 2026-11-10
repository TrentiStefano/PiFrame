#!/usr/bin/env node
// Development launcher. Gives dev builds their own state folder (PI_FRAME_HOME = ~/.piframe-dev),
// so a release daemon can keep running next to the dev one. Release installs never set
// PI_FRAME_HOME, so they keep using ~/.piframe and are not affected.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/**
 * Prepares the dev state folder. Attachments (random ids, pruned by age) are shared with the release
 * through a junction, so old sessions keep their images. Settings are copied once, then diverge.
 */
export function prepareDevHome({ releaseHome, devHome }) {
  fs.mkdirSync(devHome, { recursive: true });
  const releaseBlobs = path.join(releaseHome, 'blobs');
  const devBlobs = path.join(devHome, 'blobs');
  fs.mkdirSync(releaseBlobs, { recursive: true });
  try {
    fs.symlinkSync(releaseBlobs, devBlobs, 'junction');
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
  }
  const devConfig = path.join(devHome, 'config.json');
  const releaseConfig = path.join(releaseHome, 'config.json');
  if (!fs.existsSync(devConfig) && fs.existsSync(releaseConfig)) fs.copyFileSync(releaseConfig, devConfig);
  return devHome;
}

function main(extraArgs) {
  const releaseHome = path.join(os.homedir(), '.piframe');
  const devHome = prepareDevHome({ releaseHome, devHome: path.join(os.homedir(), '.piframe-dev') });
  console.log(`[dev] PI_FRAME_HOME=${devHome}`);
  const env = { ...process.env, PI_FRAME_HOME: devHome };
  const steps = [
    { cmd: 'pnpm', args: ['run', 'build:agentd'], cwd: repoRoot },
    { cmd: 'flutter', args: ['run', ...extraArgs], cwd: path.join(repoRoot, 'apps', 'pi_frame') },
  ];
  for (const { cmd, args, cwd } of steps) {
    // Windows needs a shell to resolve pnpm.cmd and flutter.bat.
    const result = process.platform === 'win32'
      ? spawnSync([cmd, ...args].join(' '), { cwd, env, stdio: 'inherit', shell: true })
      : spawnSync(cmd, args, { cwd, env, stdio: 'inherit' });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2));
}

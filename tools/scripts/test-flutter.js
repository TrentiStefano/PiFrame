const { spawnSync } = require('child_process');
const path = require('path');

// The Flutter/Dart projects, shared by the setup, analyze, test and format scripts.
const dirs = require('./flutter-projects.json');

// The app bundles the in-app changelog (apps/pi_frame/assets/CHANGELOG.md), generated from the root CHANGELOG.md
// and not committed: generate it first, so the tests never run against a missing or stale copy.
const sync = spawnSync(process.execPath, [path.join(__dirname, 'sync-changelog.mjs')], { stdio: 'inherit' });
if (sync.status !== 0) {
  console.error('Failed to generate apps/pi_frame/assets/CHANGELOG.md');
  process.exit(sync.status || 1);
}

for (const dir of dirs) {
  const cwd = path.resolve(process.cwd(), dir);
  console.log(`Running 'flutter test' in ${dir}...`);
  const res = spawnSync('flutter', ['test'], { cwd, stdio: 'inherit', shell: true });
  if (res.status !== 0) {
    console.error(`Flutter test failed in ${dir}`);
    process.exit(res.status || 1);
  }
}
console.log('Flutter tests passed for all projects.');

const { spawnSync } = require('child_process');
const path = require('path');
const { withChangelog } = require('./with-changelog.js');

// The Flutter/Dart projects, shared by the setup, analyze, test and format scripts.
const dirs = require('./flutter-projects.json');

// The app bundles the in-app changelog (apps/pi_frame/assets/CHANGELOG.md), generated from the root CHANGELOG.md
// and not committed: generate it first, so the tests never run against a missing or stale copy.
withChangelog(() => {
  for (const dir of dirs) {
    const cwd = path.resolve(process.cwd(), dir);
    console.log(`Running 'flutter test' in ${dir}...`);
    const res = spawnSync('flutter', ['test', '--exclude-tags', 'golden'], { cwd, stdio: 'inherit', shell: true });
    if (res.status !== 0) {
      console.error(`Flutter test failed in ${dir}`);
      process.exit(res.status || 1);
    }
  }
});
console.log('Flutter tests passed for all projects.');

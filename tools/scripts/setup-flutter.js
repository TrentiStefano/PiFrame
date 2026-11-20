const { spawnSync } = require('child_process');
const path = require('path');

// The Flutter/Dart projects, shared by the setup, analyze, test and format scripts.
const dirs = require('./flutter-projects.json');

const cmd = process.platform === 'win32' ? 'flutter.bat' : 'flutter';

// The in-app changelog asset is generated from the root CHANGELOG.md, not committed.
const sync = spawnSync(process.execPath, [path.join(__dirname, 'sync-changelog.mjs')], { stdio: 'inherit' });
if (sync.status !== 0) {
  console.error('Failed to generate apps/pi_frame/assets/CHANGELOG.md');
  process.exit(sync.status || 1);
}

for (const dir of dirs) {
  const cwd = path.resolve(process.cwd(), dir);
  console.log(`Running '${cmd} pub get' in ${dir}...`);
  const res = spawnSync('flutter', ['pub', 'get'], { cwd, stdio: 'inherit', shell: true });
  if (res.status !== 0) {
    console.error(`Failed to get pub dependencies in ${dir}`);
    process.exit(res.status || 1);
  }
}
console.log('All Flutter packages initialized successfully.');

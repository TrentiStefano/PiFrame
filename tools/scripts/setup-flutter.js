const { spawnSync } = require('child_process');
const path = require('path');

const dirs = [
  'packages/pi_frame_protocol',
  'packages/pi_frame_theme',
  'apps/pi_frame'
];

const cmd = process.platform === 'win32' ? 'flutter.bat' : 'flutter';

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

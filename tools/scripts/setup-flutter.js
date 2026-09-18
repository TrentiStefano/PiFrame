const { spawnSync } = require('child_process');
const path = require('path');

const dirs = [
  'packages/pi_crust_protocol',
  'packages/pi_crust_theme',
  'apps/pi_crust'
];

const cmd = process.platform === 'win32' ? 'flutter.bat' : 'flutter';

for (const dir of dirs) {
  const cwd = path.resolve(process.cwd(), dir);
  console.log(`Running '${cmd} pub get' in ${dir}...`);
  const res = spawnSync(cmd, ['pub', 'get'], { cwd, stdio: 'inherit' });
  if (res.status !== 0) {
    console.error(`Failed to get pub dependencies in ${dir}`);
    process.exit(res.status || 1);
  }
}
console.log('All Flutter packages initialized successfully.');

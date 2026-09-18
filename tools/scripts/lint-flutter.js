const { spawnSync } = require('child_process');
const path = require('path');

const dirs = [
  'packages/pi_crust_protocol',
  'packages/pi_crust_theme',
  'apps/pi_crust'
];

for (const dir of dirs) {
  const cwd = path.resolve(process.cwd(), dir);
  console.log(`Running 'flutter analyze' in ${dir}...`);
  const res = spawnSync('flutter', ['analyze'], { cwd, stdio: 'inherit', shell: true });
  if (res.status !== 0) {
    console.error(`Flutter analyze failed in ${dir}`);
    process.exit(res.status || 1);
  }
}
console.log('Flutter analyze passed for all projects.');

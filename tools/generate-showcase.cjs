const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const baseDir = path.resolve(__dirname, '../docs/design-evidence');

const files = [
  path.join(baseDir, 'bento-triptych-fixture-dark-wide.png'),
  path.join(baseDir, 'piframe-live-settings-frappe.png'),
  path.join(baseDir, 'bento-triptych-fixture-wide.png'),
  path.join(baseDir, 'piframe-live-settings-latte.png'),
  path.join(baseDir, 'bento-triptych-fixture-dark-compact-git.png'),
  path.join(baseDir, 'bento-triptych-fixture-dark-wide.png'),
];

// Check all exist
for (const f of files) {
  if (!fs.existsSync(f)) {
    console.error('File not found:', f);
    process.exit(1);
  }
}

// Build ffmpeg filter_complex with crossfades
// Each image is scaled to 1280x800 with padding if necessary
const inputArgs = files.map(f => `-loop 1 -t 3 -i "${f}"`).join(' ');

let filter = '';
// Scale all inputs
files.forEach((_, i) => {
  filter += `[${i}:v]scale=1280:800:force_original_aspect_ratio=decrease,pad=1280:800:(ow-iw)/2:(oh-ih)/2:color=#232634,setsar=1[v${i}];`;
});

// Chain xfade
// offsets:
// v0: 0..3s
// v1: 2.3..5.3s (offset 2.3)
// v2: 4.6..7.6s (offset 4.6)
// v3: 6.9..9.9s (offset 6.9)
// v4: 9.2..12.2s (offset 9.2)
// v5: 11.5..14.5s (offset 11.5)
const transitions = ['fade', 'fade', 'fade', 'fade', 'fade'];
let current = 'v0';
let offset = 2.3;
for (let i = 1; i < files.length; i++) {
  const nextOut = (i === files.length - 1) ? 'vout' : `xf${i}`;
  filter += `[${current}][v${i}]xfade=transition=fade:duration=0.7:offset=${offset.toFixed(1)}[${nextOut}];`;
  current = nextOut;
  offset += 2.3;
}

// Remove trailing semicolon
filter = filter.replace(/;$/, '');

const outMp4 = path.join(baseDir, 'piframe-showcase.mp4');
const outWebp = path.join(baseDir, 'piframe-showcase.webp');

console.log('Generating MP4...');
const cmdMp4 = `ffmpeg ${inputArgs} -filter_complex "${filter}" -map "[vout]" -pix_fmt yuv420p -r 24 -y "${outMp4}"`;
execSync(cmdMp4, { stdio: 'inherit' });

console.log('Generating Animated WebP...');
const cmdWebp = `ffmpeg -i "${outMp4}" -c:v libwebp -lossless 0 -q:v 70 -loop 0 -vf "fps=14,scale=800:-1" -y "${outWebp}"`;
execSync(cmdWebp, { stdio: 'inherit' });

console.log('Showcase generation finished successfully!');

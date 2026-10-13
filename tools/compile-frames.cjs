const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const framesDir = path.resolve(__dirname, '../scratch/frames');
const outDir = path.resolve(__dirname, '../docs/design-evidence');

const mp4Hero = path.join(outDir, 'hero.mp4');
const gifHero = path.join(outDir, 'hero.gif');
const webpHero = path.join(outDir, 'hero.webp');
const mp4Showcase = path.join(outDir, 'pi-crust-showcase.mp4');
const webpShowcase = path.join(outDir, 'pi-crust-showcase.webp');

console.log('1. Encoding hero.mp4...');
execSync(`ffmpeg -framerate 32 -i "${path.join(framesDir, 'frame_%05d.png')}" -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 -r 24 -y "${mp4Hero}"`, { stdio: 'inherit' });
fs.copyFileSync(mp4Hero, mp4Showcase);

console.log('2. Encoding hero.webp...');
execSync(`ffmpeg -i "${mp4Hero}" -c:v libwebp -lossless 0 -q:v 75 -loop 0 -vf "fps=16,scale=800:-2" -y "${webpHero}"`, { stdio: 'inherit' });
fs.copyFileSync(webpHero, webpShowcase);

console.log('3. Encoding hero.gif...');
const pal = path.join(framesDir, 'palette.png');
execSync(`ffmpeg -i "${mp4Hero}" -vf "fps=12,scale=720:-2:flags=lanczos,palettegen=stats_mode=diff" -y "${pal}"`, { stdio: 'inherit' });
execSync(`ffmpeg -i "${mp4Hero}" -i "${pal}" -lavfi "fps=12,scale=720:-2:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y "${gifHero}"`, { stdio: 'inherit' });

console.log('SUCCESS! Video and animation assets compiled.');

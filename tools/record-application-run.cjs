const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const showcaseUrl = 'file:///' + path.resolve(__dirname, '../docs/design-evidence/showcase.html').replace(/\\/g, '/');
const framesDir = path.resolve(__dirname, '../scratch/frames');

if (!fs.existsSync(framesDir)) {
  fs.mkdirSync(framesDir, { recursive: true });
} else {
  // Clear old frames
  fs.readdirSync(framesDir).forEach(f => fs.unlinkSync(path.join(framesDir, f)));
}

async function main() {
  console.log('1. Starting headless Chrome with remote debugging on port 9444...');
  const port = 9444;
  const chrome = spawn(chromePath, [
    '--headless=new',
    `--remote-debugging-port=${port}`,
    '--window-size=1280,800',
    '--hide-scrollbars',
    '--disable-gpu',
    showcaseUrl
  ]);

  chrome.stderr.on('data', d => {
    // suppress verbose chromium logs
  });

  // Wait 1.5s for Chrome to initialize
  await new Promise(r => setTimeout(r, 1500));

  console.log('2. Discovering CDP target...');
  const res = await fetch(`http://127.0.0.1:${port}/json`);
  const targets = await res.json();
  const pageTarget = targets.find(t => t.type === 'page');

  if (!pageTarget) {
    console.error('No page target found!');
    chrome.kill();
    process.exit(1);
  }

  console.log('3. Connecting WebSocket to:', pageTarget.webSocketDebuggerUrl);
  const ws = new WebSocket(pageTarget.webSocketDebuggerUrl);

  let frameCount = 0;
  let msgId = 1;

  function sendCmd(method, params = {}) {
    return new Promise(resolve => {
      const id = msgId++;
      const handler = (e) => {
        const data = JSON.parse(e.data);
        if (data.id === id) {
          ws.removeEventListener('message', handler);
          resolve(data.result);
        }
      };
      ws.addEventListener('message', handler);
      ws.send(JSON.stringify({ id, method, params }));
    });
  }

  await new Promise(resolve => {
    ws.addEventListener('open', resolve);
  });

  console.log('4. Enabling Page & starting screencast...');
  await sendCmd('Page.enable');

  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.method === 'Page.screencastFrame') {
      const { data, sessionId } = msg.params;
      frameCount++;
      const padded = String(frameCount).padStart(5, '0');
      const framePath = path.join(framesDir, `frame_${padded}.png`);
      fs.writeFileSync(framePath, Buffer.from(data, 'base64'));

      // Ack frame to keep stream pumping smoothly
      ws.send(JSON.stringify({
        id: msgId++,
        method: 'Page.screencastFrameAck',
        params: { sessionId }
      }));
    }
  });

  await sendCmd('Page.startScreencast', {
    format: 'png',
    quality: 95,
    everyNthFrame: 1
  });

  console.log('5. Screencast active! Recording live application run...');

  const startTime = Date.now();
  let done = false;

  while (!done && (Date.now() - startTime < 26000)) {
    await new Promise(r => setTimeout(r, 500));
    try {
      const evalRes = await sendCmd('Runtime.evaluate', { expression: 'window.demoFinished' });
      if (evalRes && evalRes.result && evalRes.result.value === true) {
        console.log('Demo reached completion signal on window!');
        done = true;
        break;
      }
    } catch (_) {}
    process.stdout.write(`\rCaptured ${frameCount} frames... (${((Date.now() - startTime)/1000).toFixed(1)}s)`);
  }

  console.log(`\n6. Finished recording! Total frames captured: ${frameCount}`);

  await sendCmd('Page.stopScreencast').catch(() => {});
  ws.close();
  chrome.kill();

  if (frameCount < 10) {
    console.error('Too few frames captured! Aborting.');
    process.exit(1);
  }

  console.log('7. Compiling frames with FFmpeg...');
  const outDir = path.resolve(__dirname, '../docs/design-evidence');
  const mp4Hero = path.join(outDir, 'hero.mp4');
  const gifHero = path.join(outDir, 'hero.gif');
  const webpHero = path.join(outDir, 'hero.webp');
  const mp4Showcase = path.join(outDir, 'pi-crust-showcase.mp4');
  const webpShowcase = path.join(outDir, 'pi-crust-showcase.webp');

  // Determine actual capture fps
  const durationSec = (Date.now() - startTime) / 1000;
  const inputFps = Math.max(12, Math.round(frameCount / durationSec));
  console.log(`Calculated capture FPS: ${inputFps}`);

  // Compile MP4
  console.log('Encoding hero.mp4...');
  execSync(`ffmpeg -framerate ${inputFps} -i "${path.join(framesDir, 'frame_%05d.png')}" -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 -r 24 -y "${mp4Hero}"`, { stdio: 'inherit' });
  fs.copyFileSync(mp4Hero, mp4Showcase);

  // Compile animated WebP
  console.log('Encoding hero.webp...');
  execSync(`ffmpeg -i "${mp4Hero}" -c:v libwebp -lossless 0 -q:v 75 -loop 0 -vf "fps=16,scale=800:-2" -y "${webpHero}"`, { stdio: 'inherit' });
  fs.copyFileSync(webpHero, webpShowcase);

  // Compile animated GIF (palettegen + paletteuse for crisp colors)
  console.log('Encoding hero.gif with optimized 256-color palette...');
  const palettePng = path.join(framesDir, 'palette.png');
  execSync(`ffmpeg -i "${mp4Hero}" -vf "fps=12,scale=720:-2:flags=lanczos,palettegen=stats_mode=diff" -y "${palettePng}"`, { stdio: 'inherit' });
  execSync(`ffmpeg -i "${mp4Hero}" -i "${palettePng}" -lavfi "fps=12,scale=720:-2:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y "${gifHero}"`, { stdio: 'inherit' });

  console.log('All formats generated successfully!');
  console.log(`- ${mp4Hero}`);
  console.log(`- ${webpHero}`);
  console.log(`- ${gifHero}`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});

#!/usr/bin/env node
/**
 * tools/showcase/mobile/capture_mobile.mjs
 *
 * Captures authentic PiFrame mobile (remote/phone) web UI screenshots and frames
 * them inside a clean iPhone 15 Pro device frame (with titanium body, Dynamic Island,
 * subtle shadow, and transparent background).
 *
 * Usage:
 *   node tools/showcase/mobile/capture_mobile.mjs [--port <port>] [--out-dir <path>]
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(import.meta.url);

// Robust playwright resolution across repo and demo tool directories
async function loadPlaywright() {
  const candidates = [
    'playwright',
    'C:/demo/tools/mobile/node_modules/playwright',
    path.resolve(__dirname, '../../../node_modules/playwright'),
  ];
  for (const candidate of candidates) {
    try {
      const mod = await import(candidate);
      if (mod && mod.chromium) return mod;
    } catch {
      try {
        const mod = require(candidate);
        if (mod && mod.chromium) return mod;
      } catch {
        // Continue search
      }
    }
  }
  throw new Error('Playwright not found. Install it with: npm install playwright');
}

// Resilient headless browser launcher
async function launchBrowser(chromium) {
  const launchOptions = {
    headless: true,
    args: [
      '--disable-extensions',
      '--disable-component-extensions-with-background-pages',
      '--disable-background-networking',
      '--no-default-browser-check',
    ],
  };

  try {
    return await chromium.launch({ ...launchOptions, channel: 'chrome' });
  } catch (err1) {
    try {
      return await chromium.launch(launchOptions);
    } catch (err2) {
      try {
        return await chromium.launch({ ...launchOptions, channel: 'msedge' });
      } catch (err3) {
        throw new Error(`Failed to launch browser: ${err1.message}; ${err2.message}; ${err3.message}`);
      }
    }
  }
}

// Discover active daemon port from runtime json if not explicitly passed
function resolveDaemonPort(cliPort) {
  if (cliPort) return Number(cliPort);

  const candidates = [
    'C:/demo/home/.piframe/runtime/daemon.json',
    path.join(process.env.USERPROFILE || '', '.piframe/runtime/daemon.json'),
  ];

  for (const file of candidates) {
    if (fs.existsSync(file)) {
      try {
        const data = JSON.parse(fs.readFileSync(file, 'utf8'));
        if (data.port) return Number(data.port);
      } catch {
        // Continue to next candidate
      }
    }
  }

  throw new Error(
    'No active PiFrame daemon found in C:/demo/home/.piframe/runtime/daemon.json. Pass --port <port> explicitly.'
  );
}

// HTML & CSS template for the titanium iPhone 15 Pro device frame
function buildDeviceFrameHtml(base64Image) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: transparent;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1540px;
    height: 3040px;
    overflow: hidden;
  }

  /* Multi-stage soft drop shadow */
  .phone-shadow-wrap {
    position: relative;
    filter: drop-shadow(0 32px 64px rgba(0, 0, 0, 0.48))
            drop-shadow(0 14px 28px rgba(0, 0, 0, 0.36));
  }

  /* Titanium outer chassis */
  .chassis {
    position: relative;
    width: 1344px;
    height: 2850px;
    border-radius: 204px;
    padding: 27px;
    background: linear-gradient(145deg,
      #787673 0%,
      #464543 25%,
      #2b2a29 50%,
      #42413f 75%,
      #6a6865 100%
    );
    box-shadow:
      inset 0 0 0 2px rgba(255, 255, 255, 0.24),
      inset 0 0 0 4px rgba(0, 0, 0, 0.7),
      inset 0 2px 4px rgba(255, 255, 255, 0.32),
      inset 0 -2px 4px rgba(0, 0, 0, 0.55);
  }

  /* Outer titanium edge highlight and chamfer */
  .chassis::before {
    content: '';
    position: absolute;
    inset: 1px;
    border-radius: 203px;
    border: 1.5px solid rgba(255, 255, 255, 0.2);
    pointer-events: none;
  }

  /* Physical hardware buttons on titanium edge */
  .button {
    position: absolute;
    background: linear-gradient(to right, #383736, #5a5856);
    border-radius: 4px 0 0 4px;
    box-shadow: -1px 0 2px rgba(0, 0, 0, 0.4);
  }
  .btn-action {
    left: -7px;
    top: 390px;
    width: 7px;
    height: 85px;
  }
  .btn-vol-up {
    left: -7px;
    top: 520px;
    width: 7px;
    height: 165px;
  }
  .btn-vol-down {
    left: -7px;
    top: 725px;
    width: 7px;
    height: 165px;
  }
  .btn-power {
    right: -7px;
    top: 575px;
    width: 7px;
    height: 245px;
    border-radius: 0 4px 4px 0;
    box-shadow: 1px 0 2px rgba(0, 0, 0, 0.4);
    background: linear-gradient(to left, #383736, #5a5856);
  }

  /* Ear speaker micro-slit centered at top edge of chassis */
  .speaker-slit {
    position: absolute;
    top: 13px;
    left: 50%;
    transform: translateX(-50%);
    width: 170px;
    height: 5px;
    border-radius: 3px;
    background: #111;
    box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.9);
    z-index: 20;
  }

  /* Screen bezel container (~1290x2796 screen inset) */
  .screen-bezel {
    position: relative;
    width: 1290px;
    height: 2796px;
    border-radius: 177px;
    overflow: hidden;
    background: #000;
    box-shadow: inset 0 0 0 2px rgba(0, 0, 0, 0.95), inset 0 0 4px rgba(0, 0, 0, 0.8);
  }

  /* The real screenshot unmodified (scaled to screen inset) */
  .screen-img {
    position: absolute;
    top: 0;
    left: 0;
    width: 1290px;
    height: 2796px;
    object-fit: fill;
    display: block;
    user-select: none;
  }

  /* Dynamic Island */
  .dynamic-island {
    position: absolute;
    top: 32px;
    left: 50%;
    transform: translateX(-50%);
    width: 310px;
    height: 90px;
    background: #000000;
    border-radius: 45px;
    z-index: 100;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 24px;
    box-shadow: 0 0 1px 1px rgba(0, 0, 0, 0.7);
  }

  /* Front camera lens & TrueDepth sensor inside island */
  .camera-sensor-cluster {
    position: absolute;
    right: 36px;
    top: 50%;
    transform: translateY(-50%);
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: radial-gradient(circle at 40% 40%, #151e36 0%, #080d18 55%, #020408 85%);
    box-shadow: inset 0 0 3px rgba(0, 100, 200, 0.25);
  }
  .camera-lens-reflection {
    position: absolute;
    top: 9px;
    left: 9px;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(100, 160, 255, 0.45) 0%, transparent 80%);
  }
  .truedepth-sensor {
    position: absolute;
    left: 42px;
    top: 50%;
    transform: translateY(-50%);
    width: 26px;
    height: 26px;
    border-radius: 50%;
    background: radial-gradient(circle, #08080a 0%, #000000 80%);
  }

  /* Screen glass sheen */
  .screen-sheen {
    position: absolute;
    inset: 0;
    border-radius: 177px;
    background: linear-gradient(130deg,
      rgba(255, 255, 255, 0.04) 0%,
      rgba(255, 255, 255, 0.015) 30%,
      transparent 60%
    );
    pointer-events: none;
    z-index: 90;
  }
</style>
</head>
<body>

<div class="phone-shadow-wrap">
  <div class="chassis">
    <!-- Physical buttons -->
    <div class="button btn-action"></div>
    <div class="button btn-vol-up"></div>
    <div class="button btn-vol-down"></div>
    <div class="button btn-power"></div>

    <!-- Ear speaker -->
    <div class="speaker-slit"></div>

    <!-- Screen Bezel & Content -->
    <div class="screen-bezel">
      <img class="screen-img" src="data:image/png;base64,${base64Image}" alt="Screen" />
      
      <!-- Dynamic Island -->
      <div class="dynamic-island">
        <div class="truedepth-sensor"></div>
        <div class="camera-sensor-cluster">
          <div class="camera-lens-reflection"></div>
        </div>
      </div>

      <!-- Glass Sheen -->
      <div class="screen-sheen"></div>
    </div>
  </div>
</div>

</body>
</html>`;
}

// Render the device frame containing the raw screenshot to transparent PNG
async function frameScreenshot(browser, srcImagePath, outIphonePath) {
  const imgBase64 = fs.readFileSync(srcImagePath).toString('base64');
  const html = buildDeviceFrameHtml(imgBase64);

  const page = await browser.newPage({
    viewport: { width: 1540, height: 3040 },
    deviceScaleFactor: 1,
  });

  await page.setContent(html);
  await page.waitForTimeout(500);

  await page.screenshot({
    path: outIphonePath,
    omitBackground: true,
  });

  await page.close();
}

async function main() {
  const args = process.argv.slice(2);
  let cliPort = null;
  let outDir = 'C:/demo/remote-shots';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--port' && args[i + 1]) {
      cliPort = args[++i];
    } else if (args[i] === '--out-dir' && args[i + 1]) {
      outDir = args[++i];
    }
  }

  const port = resolveDaemonPort(cliPort);
  console.log(`[PiFrame Mobile] Target daemon port: ${port}`);
  console.log(`[PiFrame Mobile] Target output dir: ${outDir}`);

  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }

  const { chromium } = await loadPlaywright();
  const browser = await launchBrowser(chromium);
  console.log('[PiFrame Mobile] Headless browser launched');

  try {
    // iPhone 15 Pro viewport: 393x852, deviceScaleFactor 3, isMobile: true, hasTouch: true
    const context = await browser.newContext({
      viewport: { width: 393, height: 852 },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
      bypassCSP: true,
      userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    });

    // Abort third-party network proxy / userscript injections (e.g. AdGuard Assistant)
    await context.route(/adguard/i, route => route.abort());

    const page = await context.newPage();

    console.log(`[PiFrame Mobile] Loading http://127.0.0.1:${port}/ ...`);
    await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'domcontentloaded' });

    console.log('[PiFrame Mobile] Waiting 12s for Flutter Canvaskit to initialize...');
    await page.waitForTimeout(12000);

    // 1. Capture landing screen
    const landingPath = path.join(outDir, 'landing.png');
    await page.screenshot({ path: landingPath });
    console.log(`[PiFrame Mobile] Saved: ${landingPath}`);

    // 2. Open drawer and expand orbit-api folder
    console.log('[PiFrame Mobile] Opening sessions drawer (tap hamburger menu at 25, 25)...');
    await page.touchscreen.tap(25, 25);
    await page.waitForTimeout(1500);

    console.log('[PiFrame Mobile] Expanding orbit-api folder (tap folder row at 140, 180)...');
    await page.touchscreen.tap(140, 180);
    await page.waitForTimeout(1500);

    const drawerPath = path.join(outDir, 'drawer.png');
    await page.screenshot({ path: drawerPath });
    console.log(`[PiFrame Mobile] Saved: ${drawerPath}`);

    // 3. Open session: "Explain the orbit model"
    console.log('[PiFrame Mobile] Selecting "Explain the orbit model" session (tap at 140, 310)...');
    await page.touchscreen.tap(140, 310);
    await page.waitForTimeout(4000);

    console.log('[PiFrame Mobile] Waiting 6s for session transcript and composer...');
    await page.waitForTimeout(6000);

    const sessionPath = path.join(outDir, 'session.png');
    await page.screenshot({ path: sessionPath });
    console.log(`[PiFrame Mobile] Saved: ${sessionPath}`);

    // 4. Render framed iPhone screenshot
    console.log('[PiFrame Mobile] Rendering iPhone 15 Pro device frame with transcript...');
    const iphonePath = path.join(outDir, 'iphone.png');
    await frameScreenshot(browser, sessionPath, iphonePath);
    console.log(`[PiFrame Mobile] Saved framed image: ${iphonePath}`);

    // 5. Render framed landing screenshot
    console.log('[PiFrame Mobile] Rendering iPhone 15 Pro device frame with landing...');
    const iphoneLandingPath = path.join(outDir, 'iphone_landing.png');
    await frameScreenshot(browser, landingPath, iphoneLandingPath);
    console.log(`[PiFrame Mobile] Saved framed image: ${iphoneLandingPath}`);

    console.log('\n[PiFrame Mobile] Capture and framing completed successfully!');
  } finally {
    await browser.close();
  }
}

main().catch(err => {
  console.error('[PiFrame Mobile] Execution error:', err);
  process.exit(1);
});

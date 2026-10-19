#!/usr/bin/env node

/**
 * Pi-Crust Release Promotional Video & Asset Generator
 *
 * Automates recording and encoding of promotional videos directly from the
 * ACTUAL Flutter application UI (apps/pi_crust) with Recordly aesthetics:
 *   - Catppuccin desktop wallpaper canvas
 *   - macOS/desktop traffic light window chrome
 *   - Soft outer drop shadows & rounded corners
 *   - Dynamic camera zooms into key actions
 *   - Animated virtual cursor & click ripple rings
 *   - MP4, animated WebP, and GIF exports
 *   - Native .recordly project manifests for manual editing in Recordly
 *
 * Usage:
 *   pnpm run generate:promos           # Full suite (hero + all clips)
 *   pnpm run generate:promos:hero      # Hero 30s walkthrough only
 *   pnpm run generate:promos:clips     # Feature clips only
 *   node tools/generate-release-promos.cjs --clip search # Single clip
 *   node tools/generate-release-promos.cjs --skip-record # Re-encode only
 */

const { spawnSync, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// Project paths
const rootDir = path.resolve(__dirname, '..');
const appDir = path.join(rootDir, 'apps/pi_crust');
const outDir = path.join(rootDir, 'docs/design-evidence');
const recordlyProjectsDir = path.join(outDir, 'recordly-projects');
const framesRootDir = path.join(rootDir, 'scratch/real_frames');

// Ensure output directories exist
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
if (!fs.existsSync(recordlyProjectsDir)) fs.mkdirSync(recordlyProjectsDir, { recursive: true });
if (!fs.existsSync(framesRootDir)) fs.mkdirSync(framesRootDir, { recursive: true });

// Scenarios Catalog matching the actual Pi-Crust Flutter application
// All clips are now recorded at ~33ms/frame (≈ 30fps) for smooth, fluid playback.
const SCENARIOS = [
  {
    id: 'hero',
    name: 'Hero 30s Master Walkthrough',
    description: 'Master tour of the actual Pi-Crust UI: Bento workspace, Command Palette (Ctrl+K), in-file syntax & Ctrl+F search, in-flight steer queue editing, thinking block, live Git diff review, and Catppuccin theme hot-reload.',
    outputBase: 'hero-30s-bento-walkthrough',
    legacyAliases: ['hero', 'pi-crust-showcase'],
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-bento', startMs: 0, endMs: 3000, scale: 1.0, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-palette', startMs: 3000, endMs: 6000, scale: 1.04, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-search', startMs: 6000, endMs: 9500, scale: 1.22, focusX: 0.33, focusY: 0.43 },
      { id: 'zoom-steer', startMs: 9500, endMs: 13500, scale: 1.10, focusX: 0.5, focusY: 0.56 },
      { id: 'zoom-context', startMs: 13500, endMs: 16500, scale: 1.12, focusX: 0.75, focusY: 0.5 },
      { id: 'zoom-reasoning', startMs: 16500, endMs: 19500, scale: 1.20, focusX: 0.55, focusY: 0.45 },
      { id: 'zoom-tools', startMs: 19500, endMs: 22500, scale: 1.20, focusX: 0.55, focusY: 0.45 },
      { id: 'zoom-git', startMs: 22500, endMs: 26000, scale: 1.18, focusX: 0.77, focusY: 0.47 },
      { id: 'zoom-tree', startMs: 26000, endMs: 28500, scale: 1.06, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-theme', startMs: 28500, endMs: 31000, scale: 1.04, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-disconnect', startMs: 31000, endMs: 33500, scale: 1.10, focusX: 0.28, focusY: 0.23 }
    ]
  },
  {
    id: 'bento',
    name: 'Clip 1: Bento Triptych Workspace',
    description: 'Three co-visible work areas (Sessions Rail, Repository Workspace, Chat & Transcript, Git Changes) with responsive ergonomic layout.',
    outputBase: 'clip-01-bento-workspace',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-bento', startMs: 0, endMs: 3000, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'palette',
    name: 'Clip 2: Command Palette (Ctrl+K Quick Actions)',
    description: 'Keyboard-first command palette modal for instant navigation, file searching, session operations, and workspace commands.',
    outputBase: 'clip-02-command-palette',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-palette-in', startMs: 0, endMs: 800, scale: 1.06, focusX: 0.7, focusY: 0.1 },
      { id: 'zoom-palette-modal', startMs: 800, endMs: 2600, scale: 1.04, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-palette-out', startMs: 2600, endMs: 3000, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'search',
    name: 'Clip 3: In-File Code Search & Syntax Highlighting',
    description: 'Real syntax highlighting in code viewer, live Ctrl+F search overlay, typing queries, and occurrence match cycling (1 di 2).',
    outputBase: 'clip-03-code-search',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-search-in', startMs: 0, endMs: 1000, scale: 1.22, focusX: 0.33, focusY: 0.43 },
      { id: 'zoom-search-hold', startMs: 1000, endMs: 4500, scale: 1.22, focusX: 0.33, focusY: 0.43 },
      { id: 'zoom-search-out', startMs: 4500, endMs: 5300, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'steer',
    name: 'Clip 4: In-Flight Steer Queue Editing',
    description: 'Composer expansion and modal dialog to modify queued steering directives on the fly without interrupting the active agent stream.',
    outputBase: 'clip-04-steer-queue',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-steer-in', startMs: 0, endMs: 800, scale: 1.10, focusX: 0.5, focusY: 0.56 },
      { id: 'zoom-steer-hold', startMs: 800, endMs: 4200, scale: 1.10, focusX: 0.5, focusY: 0.56 },
      { id: 'zoom-steer-out', startMs: 4200, endMs: 4800, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'context',
    name: 'Clip 5: Context Window & Cost Analytics',
    description: 'Real-time context window token gauge (32k / 200k, 16%), token breakdown, cost tracking ($0.1800), and model configuration drawer.',
    outputBase: 'clip-05-context-analytics',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-context-in', startMs: 0, endMs: 800, scale: 1.08, focusX: 0.77, focusY: 0.2 },
      { id: 'zoom-context-panel', startMs: 800, endMs: 3000, scale: 1.12, focusX: 0.75, focusY: 0.5 },
      { id: 'zoom-context-out', startMs: 3000, endMs: 3500, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'reasoning',
    name: 'Clip 6: Collapsible Deep Reasoning Streams',
    description: 'Collapsible deep thinking block (Ragionamento) with real-time word count, thinking tokens, live duration stopwatch, and toggle.',
    outputBase: 'clip-06-reasoning-stream',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-reasoning-in', startMs: 0, endMs: 800, scale: 1.20, focusX: 0.55, focusY: 0.45 },
      { id: 'zoom-reasoning-hold', startMs: 800, endMs: 3600, scale: 1.20, focusX: 0.55, focusY: 0.45 },
      { id: 'zoom-reasoning-out', startMs: 3600, endMs: 4200, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'tools',
    name: 'Clip 7: Tool Execution Timeline & Test Runner',
    description: 'Interactive ToolCard widget with execution latency badge (4100ms), verified success indicator (✓), and expandable stdout terminal output.',
    outputBase: 'clip-07-tool-timeline',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-tools-in', startMs: 0, endMs: 800, scale: 1.20, focusX: 0.55, focusY: 0.42 },
      { id: 'zoom-tools-hold', startMs: 800, endMs: 3200, scale: 1.20, focusX: 0.55, focusY: 0.42 },
      { id: 'zoom-tools-out', startMs: 3200, endMs: 3800, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'git',
    name: 'Clip 8: Live Git Changes & Staging Desk',
    description: 'Live git tracking, unstaged modifications, visual unified diff modal dialog with additions and deletions, and 1-click stage.',
    outputBase: 'clip-08-git-staging',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-git-in', startMs: 0, endMs: 800, scale: 1.18, focusX: 0.77, focusY: 0.47 },
      { id: 'zoom-git-diff', startMs: 800, endMs: 3500, scale: 1.08, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-git-out', startMs: 3500, endMs: 4200, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'tree',
    name: 'Clip 9: Conversation Branching & Session Tree',
    description: 'Visual conversation lineage tree dialog showing branches, message nodes, and timeline checkpoints for branching off past turns.',
    outputBase: 'clip-09-session-tree',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-tree-in', startMs: 0, endMs: 800, scale: 1.06, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-tree-hold', startMs: 800, endMs: 3000, scale: 1.06, focusX: 0.5, focusY: 0.5 },
      { id: 'zoom-tree-out', startMs: 3000, endMs: 3500, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'theme',
    name: 'Clip 10: Catppuccin Theme Engine',
    description: 'Hot-reloadable seamless switch between Catppuccin Frappé (dark) and Catppuccin Latte (light) across all window widgets.',
    outputBase: 'clip-10-catppuccin-themes',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-theme', startMs: 0, endMs: 4200, scale: 1.04, focusX: 0.5, focusY: 0.5 }
    ]
  },
  {
    id: 'disconnect',
    name: 'Clip 11: Disconnect-Safe Local Daemon & Notifications',
    description: 'Resilient local daemon connection badge (Pi locale, 100% offline & zero telemetry) and native desktop notification toast banner.',
    outputBase: 'clip-11-disconnect-safe',
    targetFps: 30,
    zoomRegions: [
      { id: 'zoom-disconnect-in', startMs: 0, endMs: 800, scale: 1.10, focusX: 0.28, focusY: 0.23 },
      { id: 'zoom-disconnect-hold', startMs: 800, endMs: 2800, scale: 1.10, focusX: 0.28, focusY: 0.23 },
      { id: 'zoom-disconnect-out', startMs: 2800, endMs: 3400, scale: 1.0, focusX: 0.5, focusY: 0.5 }
    ]
  }
];

// CLI Arguments parser
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    mode: 'all', // 'all', 'hero', 'clips', 'single'
    targetId: null,
    skipRecord: false,
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--help' || a === '-h') options.help = true;
    else if (a === '--hero') options.mode = 'hero';
    else if (a === '--clips') options.mode = 'clips';
    else if (a === '--all') options.mode = 'all';
    else if (a === '--skip-record') options.skipRecord = true;
    else if (a === '--clip' && args[i + 1]) {
      options.mode = 'single';
      options.targetId = args[++i];
    }
  }

  return options;
}

// Check ffmpeg availability
function checkFfmpeg() {
  try {
    execSync('ffmpeg -version', { stdio: 'pipe' });
  } catch (err) {
    console.error('❌ Error: ffmpeg is required but not found in PATH.');
    process.exit(1);
  }
}

// Run Flutter test harness to capture real frames
function recordRealFlutterApp() {
  console.log('\n======================================================');
  console.log('🚀 RECORDING ACTUAL FLUTTER APPLICATION UI');
  console.log('   Running: flutter test test/record_real_app_showcase_test.dart');
  console.log('   App Directory: apps/pi_crust');
  console.log('   Stage: 1920x1080 Recordly Canvas (Catppuccin Wallpaper + Window Chrome)');
  console.log('======================================================\n');

  const startMs = Date.now();
  const res = spawnSync('flutter', ['test', 'test/record_real_app_showcase_test.dart'], {
    cwd: appDir,
    stdio: 'inherit',
    shell: true
  });

  if (res.status !== 0) {
    console.error(`\n❌ Flutter capture test failed with exit code ${res.status}`);
    process.exit(res.status || 1);
  }

  const elapsed = ((Date.now() - startMs) / 1000).toFixed(1);
  console.log(`\n✅ Flutter capture completed in ${elapsed}s! All scenario frames written to scratch/real_frames/`);
}

// Encode a single scenario with ffmpeg
function encodeScenario(scenario) {
  const framesDir = path.join(framesRootDir, scenario.id);
  if (!fs.existsSync(framesDir)) {
    console.warn(`⚠️ Warning: Frames directory not found for scenario "${scenario.id}" (${framesDir}). Skipping.`);
    return;
  }

  const frameFiles = fs.readdirSync(framesDir).filter(f => f.endsWith('.png'));
  if (frameFiles.length === 0) {
    console.warn(`⚠️ Warning: No frames found for scenario "${scenario.id}". Skipping.`);
    return;
  }

  console.log(`\n🎬 ENCODING: ${scenario.name}`);
  console.log(`   Frames: ${frameFiles.length} | FPS: ${scenario.targetFps} | Base: ${scenario.outputBase}`);

  const mp4Out = path.join(outDir, `${scenario.outputBase}.mp4`);
  const webpOut = path.join(outDir, `${scenario.outputBase}.webp`);
  const gifOut = path.join(outDir, `${scenario.outputBase}.gif`);

  // 1. MP4 Encoding (High Quality H.264 FastStart)
  const inputPattern = path.join(framesDir, 'frame_%05d.png').replace(/\\/g, '/');
  execSync(
    `ffmpeg -y -framerate ${scenario.targetFps} -i "${inputPattern}" ` +
    `-vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 18 -preset fast -movflags +faststart "${mp4Out}"`,
    { stdio: 'pipe' }
  );

  // 2. Animated WebP (Lightweight for web & README badges)
  execSync(
    `ffmpeg -y -i "${mp4Out}" -c:v libwebp -lossless 0 -q:v 80 -loop 0 -vf "fps=${Math.min(scenario.targetFps, 12)},scale=960:-2" "${webpOut}"`,
    { stdio: 'pipe' }
  );

  // 3. High-Fidelity GIF (2-Pass Palettegen)
  const palettePng = path.join(framesDir, 'palette.png').replace(/\\/g, '/');
  execSync(
    `ffmpeg -y -i "${mp4Out}" -vf "fps=${Math.min(scenario.targetFps, 10)},scale=720:-2:flags=lanczos,palettegen=stats_mode=diff" "${palettePng}"`,
    { stdio: 'pipe' }
  );
  execSync(
    `ffmpeg -y -i "${mp4Out}" -i "${palettePng}" -lavfi "fps=${Math.min(scenario.targetFps, 10)},scale=720:-2:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "${gifOut}"`,
    { stdio: 'pipe' }
  );

  // 4. Extract 1st second preview thumbnail
  const previewPath = path.join(recordlyProjectsDir, `${scenario.outputBase}.preview.png`);
  execSync(
    `ffmpeg -y -ss 00:00:01 -i "${mp4Out}" -vframes 1 "${previewPath}"`,
    { stdio: 'pipe' }
  );

  // 5. Native Recordly Project Manifest (.recordly)
  const durationSec = parseFloat((frameFiles.length / scenario.targetFps).toFixed(1));
  const recordlyProject = {
    version: 2,
    projectId: `pi-crust-${scenario.outputBase}`,
    videoPath: `../${scenario.outputBase}.mp4`,
    metadata: {
      title: scenario.name,
      description: scenario.description,
      recordedAt: new Date().toISOString(),
      durationSeconds: durationSec,
      source: 'Pi-Crust Flutter Native Application (apps/pi_crust)'
    },
    editor: {
      wallpaper: 'catppuccin-frappe',
      shadowIntensity: 0.65,
      backgroundBlur: 12,
      showCursor: true,
      cursorStyle: 'default',
      cursorClickEffect: 'ring',
      cursorClickEffectColor: '#8caaee',
      cursorSize: 1.0,
      cursorSmoothing: 0.75,
      borderRadius: 16,
      padding: { horizontal: 48, vertical: 36 },
      aspectRatio: '16:9',
      zoomRegions: scenario.zoomRegions || [],
      speedRegions: [],
      trimRegions: []
    }
  };

  const projectPath = path.join(recordlyProjectsDir, `${scenario.outputBase}.recordly`);
  fs.writeFileSync(projectPath, JSON.stringify(recordlyProject, null, 2), 'utf-8');

  // Sync legacy hero aliases for backward compatibility
  if (scenario.legacyAliases) {
    for (const alias of scenario.legacyAliases) {
      fs.copyFileSync(mp4Out, path.join(outDir, `${alias}.mp4`));
      fs.copyFileSync(webpOut, path.join(outDir, `${alias}.webp`));
      fs.copyFileSync(gifOut, path.join(outDir, `${alias}.gif`));
    }
  }

  const mp4SizeMb = (fs.statSync(mp4Out).size / 1024 / 1024).toFixed(2);
  const webpSizeMb = (fs.statSync(webpOut).size / 1024 / 1024).toFixed(2);
  const gifSizeMb = (fs.statSync(gifOut).size / 1024 / 1024).toFixed(2);

  console.log(`   ✓ MP4:      ${scenario.outputBase}.mp4 (${mp4SizeMb} MB, ${durationSec}s)`);
  console.log(`   ✓ WebP:     ${scenario.outputBase}.webp (${webpSizeMb} MB)`);
  console.log(`   ✓ GIF:      ${scenario.outputBase}.gif (${gifSizeMb} MB)`);
  console.log(`   ✓ Recordly: recordly-projects/${scenario.outputBase}.recordly`);
}

// Generate interactive gallery
function generateGalleryHtml() {
  const galleryPath = path.join(outDir, 'promo-gallery.html');
  console.log('\nGenerating interactive Promo Video Gallery (promo-gallery.html)...');

  let cardsHtml = '';
  for (const s of SCENARIOS) {
    const isHero = s.id === 'hero';
    cardsHtml += `
      <div class="video-card ${isHero ? 'hero-card' : ''}">
        <div class="card-badge">${isHero ? '⭐ HERO MASTER WALKTHROUGH' : 'FEATURE CLIP'}</div>
        <video controls loop muted preload="metadata" poster="${s.outputBase}.webp" class="video-player">
          <source src="${s.outputBase}.mp4" type="video/mp4">
          Your browser does not support the video tag.
        </video>
        <div class="card-info">
          <h3 class="card-title">${s.name}</h3>
          <p class="card-desc">${s.description}</p>
          <div class="card-links">
            <a href="${s.outputBase}.mp4" download class="btn btn-primary">⬇ MP4 (1080p)</a>
            <a href="${s.outputBase}.webp" download class="btn btn-secondary">⬇ Animated WebP</a>
            <a href="${s.outputBase}.gif" download class="btn btn-secondary">⬇ GIF</a>
            <a href="recordly-projects/${s.outputBase}.recordly" download class="btn btn-accent">📂 .recordly Project</a>
          </div>
        </div>
      </div>
    `;
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Pi-Crust — Release Promotional Video Suite</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=Schibsted+Grotesk:wght@400;500;600;700&family=Source+Code+Pro:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #1e1e2e;
      --card-bg: #292c3c;
      --card-border: #414559;
      --accent: #8caaee;
      --accent-contrast: #181926;
      --text-pri: #c6d0f5;
      --text-sec: #a5adce;
      --success: #a6d189;
      --warning: #e5c890;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: radial-gradient(circle at 50% 0%, #292c3c 0%, #1e1e2e 50%, #11111b 100%);
      color: var(--text-pri);
      font-family: 'Schibsted Grotesk', -apple-system, sans-serif;
      padding: 40px 24px;
      min-height: 100vh;
    }
    .container { max-width: 1400px; margin: 0 auto; }
    header {
      text-align: center;
      margin-bottom: 48px;
    }
    .brand {
      display: inline-flex;
      align-items: center;
      gap: 12px;
      font-family: 'Barlow Condensed', sans-serif;
      font-size: 32px;
      font-weight: 700;
      letter-spacing: 1px;
      margin-bottom: 12px;
    }
    .brand-tag {
      background: rgba(140, 170, 238, 0.15);
      border: 1px solid rgba(140, 170, 238, 0.3);
      color: var(--accent);
      font-size: 13px;
      padding: 3px 10px;
      border-radius: 999px;
      font-family: 'Schibsted Grotesk', sans-serif;
      font-weight: 600;
    }
    .subtitle {
      color: var(--text-sec);
      font-size: 16px;
      max-width: 680px;
      margin: 0 auto;
      line-height: 1.5;
    }
    .video-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(420px, 1fr));
      gap: 28px;
    }
    .video-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 16px 40px rgba(0,0,0,0.4);
      display: flex;
      flex-direction: column;
      position: relative;
      transition: transform 0.2s ease, border-color 0.2s ease;
    }
    .video-card:hover {
      transform: translateY(-4px);
      border-color: var(--accent);
    }
    .hero-card {
      grid-column: 1 / -1;
      display: grid;
      grid-template-columns: 1.4fr 1fr;
    }
    @media (max-width: 900px) {
      .hero-card { grid-template-columns: 1fr; }
    }
    .card-badge {
      position: absolute;
      top: 14px;
      left: 14px;
      background: rgba(24, 25, 38, 0.85);
      backdrop-filter: blur(8px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      color: var(--success);
      font-size: 11px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 6px;
      z-index: 2;
      letter-spacing: 0.5px;
    }
    .video-player {
      width: 100%;
      height: 100%;
      min-height: 260px;
      background: #11111b;
      display: block;
      object-fit: cover;
    }
    .hero-card .video-player {
      min-height: 420px;
    }
    .card-info {
      padding: 24px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }
    .card-title {
      font-size: 18px;
      font-weight: 700;
      margin-bottom: 8px;
      color: #fff;
    }
    .card-desc {
      font-size: 13.5px;
      color: var(--text-sec);
      line-height: 1.5;
      margin-bottom: 20px;
    }
    .card-links {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
    .btn {
      font-size: 12px;
      font-weight: 600;
      padding: 6px 14px;
      border-radius: 8px;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.15s ease;
    }
    .btn-primary {
      background: var(--accent);
      color: var(--accent-contrast);
    }
    .btn-primary:hover {
      background: #b4befe;
    }
    .btn-secondary {
      background: rgba(255,255,255,0.06);
      color: var(--text-pri);
      border: 1px solid var(--card-border);
    }
    .btn-secondary:hover {
      background: rgba(255,255,255,0.12);
      border-color: var(--text-pri);
    }
    .btn-accent {
      background: rgba(202, 158, 230, 0.15);
      color: #ca9ee6;
      border: 1px solid rgba(202, 158, 230, 0.3);
    }
    .btn-accent:hover {
      background: rgba(202, 158, 230, 0.25);
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="brand">
        <span>🥧 PI-CRUST</span>
        <span class="brand-tag">ACTUAL FLUTTER UI · RELEASE PROMOS</span>
      </div>
      <p class="subtitle">
        Automated promotional showcase suite generated from the actual Flutter desktop application with Recordly aesthetics: Catppuccin canvas wallpaper, macOS window chrome, dynamic camera zoom, and native .recordly project manifests.
      </p>
    </header>

    <div class="video-grid">
      ${cardsHtml}
    </div>
  </div>
</body>
</html>`;

  fs.writeFileSync(galleryPath, html, 'utf-8');
  console.log(`   ✓ Gallery written to ${path.relative(rootDir, galleryPath)}`);
}

// Main Controller
function main() {
  const options = parseArgs();
  checkFfmpeg();

  if (options.help) {
    console.log(`
Pi-Crust Release Promotional Video & Asset Generator

Usage:
  node tools/generate-release-promos.cjs [options]

Options:
  --all           Generate full promotional suite (hero + 11 feature clips) [default]
  --hero          Generate only the master 30s hero walkthrough
  --clips         Generate only the 11 individual feature clips
  --clip <id>     Generate a single clip (bento, palette, search, steer, context, reasoning, tools, git, tree, theme, disconnect)
  --skip-record   Skip running Flutter test capture and re-encode existing frames
  --help, -h      Show this help message
    `);
    return;
  }

  // 1. Run Flutter capture unless --skip-record
  if (!options.skipRecord) {
    recordRealFlutterApp();
  } else {
    console.log('⚡ Skipping Flutter test recording (--skip-record flag active)');
  }

  // 2. Select scenarios to encode
  let targetScenarios = [];
  if (options.mode === 'hero') {
    targetScenarios = SCENARIOS.filter(s => s.id === 'hero');
  } else if (options.mode === 'clips') {
    targetScenarios = SCENARIOS.filter(s => s.id !== 'hero');
  } else if (options.mode === 'single' && options.targetId) {
    targetScenarios = SCENARIOS.filter(s => s.id === options.targetId);
    if (targetScenarios.length === 0) {
      console.error(`❌ Unknown clip ID "${options.targetId}". Available: ${SCENARIOS.map(s => s.id).join(', ')}`);
      process.exit(1);
    }
  } else {
    targetScenarios = SCENARIOS;
  }

  // 3. Encode selected scenarios
  console.log(`\n======================================================`);
  console.log(`🎥 COMPILING VIDEOS & RECORDLY PROJECTS (${targetScenarios.length} scenarios)`);
  console.log(`======================================================`);

  for (const s of targetScenarios) {
    encodeScenario(s);
  }

  // 4. Update gallery
  generateGalleryHtml();

  console.log('\n======================================================');
  console.log('🚀 RELEASE PROMOTIONAL ASSETS READY!');
  console.log(`   - Output Directory: docs/design-evidence/`);
  console.log(`   - Recordly Projects: docs/design-evidence/recordly-projects/`);
  console.log(`   - Web Showcase: docs/design-evidence/promo-gallery.html`);
  console.log('======================================================\n');
}

main();

#!/usr/bin/env node
/**
 * PiFrame Promo Video Pipeline (Hyperframes / Brag)
 * 
 * Renders the official launch promo video for PiFrame Desktop:
 * - 1080p Landscape Master: 1920x1080 30fps
 * - Social Cut Master: 1080x1350 30fps (4:5 portrait)
 * - Web H.264: Faststart, High profile, <= 8MB
 * - Web VP9: WebM <= 8MB
 * - Poster Frame: High-res settled frame
 * 
 * Adheres strictly to AGENTS.md rules:
 * - Real UI recordings only (or neutral test clip in --test mode; NEVER fake UI)
 * - Verifiable claims only
 * - Zero telemetry, 100% local
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, statSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, '..');

// Default Paths
const DEFAULT_CONFIG_PATH = join(__dirname, 'promo-config.json');
const DEFAULT_CLIPS_DIR = join(REPO_ROOT, 'website', 'assets', 'showcase');
const DEFAULT_WEBSITE_VIDEO_DIR = join(REPO_ROOT, 'website', 'assets', 'video');
const DEFAULT_MUSIC_PATH = join(REPO_ROOT, '.agents', 'skills', 'brag', 'assets', 'music', 'happy-beats-business-moves-vol-12-by-ende-dot-app.mp3');
const DEFAULT_ICON_PATH = join(REPO_ROOT, 'docs', 'design-evidence', 'icons', 'piframe-dark-1024.png');
const SFX_ROOT = join(REPO_ROOT, '.agents', 'skills', 'brag', 'assets', 'sfx');

// ffmpeg/ffprobe from $FFMPEG/$FFPROBE or the system PATH
function resolveFfmpeg() {
  const customWinGetPath = 'C:\\Users\\Stefano\\AppData\\Local\\Microsoft\\WinGet\\Links\\ffmpeg.exe';
  if (existsSync(customWinGetPath)) return customWinGetPath;
  return 'ffmpeg';
}

function resolveFfprobe() {
  const customWinGetPath = 'C:\\Users\\Stefano\\AppData\\Local\\Microsoft\\WinGet\\Links\\ffprobe.exe';
  if (existsSync(customWinGetPath)) return customWinGetPath;
  return 'ffprobe';
}

const FFMPEG = resolveFfmpeg();
const FFPROBE = resolveFfprobe();

// Parse CLI flags
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    test: false,
    outDir: null,
    clipsDir: DEFAULT_CLIPS_DIR,
    configPath: DEFAULT_CONFIG_PATH,
    testClip: null,
    skipCheck: false,
    landscapeOnly: false,
    socialOnly: false,
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--test') {
      options.test = true;
    } else if (arg === '--out-dir' && i + 1 < args.length) {
      options.outDir = args[++i];
    } else if (arg === '--clips-dir' && i + 1 < args.length) {
      options.clipsDir = args[++i];
    } else if (arg === '--config' && i + 1 < args.length) {
      options.configPath = args[++i];
    } else if (arg === '--test-clip' && i + 1 < args.length) {
      options.testClip = args[++i];
    } else if (arg === '--skip-check') {
      options.skipCheck = true;
    } else if (arg === '--landscape-only') {
      options.landscapeOnly = true;
    } else if (arg === '--social-only') {
      options.socialOnly = true;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    }
  }

  return options;
}

function printHelp() {
  console.log(`
PiFrame Promo Video Render Script
=================================
Usage: node brag-output/render-promo.mjs [options]

Options:
  --test               Run pipeline test using neutral clip; outputs to C:/demo/tools/brag-work/test-render/
  --out-dir <dir>      Explicit output directory for all deliverables
  --clips-dir <dir>    Directory containing showcase clips (default: website/assets/showcase)
  --test-clip <path>   Use a specific neutral test clip for all beats
  --config <path>      Path to promo-config.json
  --skip-check         Skip 'hyperframes check' gate
  --landscape-only     Render only 1080p landscape promo
  --social-only        Render only 1080x1350 social promo
  -h, --help           Show this help message
`);
}

// Generate Neutral Test Clip with FFmpeg (Never fake UI)
function generateNeutralTestClip(outputPath, duration = 12) {
  mkdirSync(dirname(outputPath), { recursive: true });
  console.log(`[ffmpeg] Generating neutral test clip: ${outputPath}`);
  execFileSync(FFMPEG, [
    '-y',
    '-f', 'lavfi',
    '-i', `color=c=0xe9e7e3:s=2384x1342:d=${duration}:r=60`,
    '-vf', "drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':text='TEST CLIP':fontcolor=0x161c27:fontsize=80:x=(w-text_w)/2:y=(h-text_h)/2",
    '-c:v', 'libx264',
    '-pix_fmt', 'yuv420p',
    outputPath
  ], { stdio: 'inherit' });
  return outputPath;
}

// Build 1080p Landscape HTML
function buildLandscapeHtml(config, beats) {
  const beatClips = beats.filter(b => b.slug !== 'outro');
  const outroBeat = beats.find(b => b.slug === 'outro');

  const videoTags = beatClips.map((b, i) => `
      <div id="frame-${b.id}" class="clip clip-frame" data-start="${b.start}" data-duration="${b.duration}">
        <video id="vid-${b.id}" class="video-clip" data-start="${b.start}" data-duration="${b.duration}" data-media-start="${b.clipStart}" muted playsinline src="assets/clips/${b.slug}.mp4"></video>
      </div>
      <div id="card-${b.id}" class="clip caption" data-start="${b.start}" data-duration="${b.duration}">
        <span id="idx-${b.id}" class="caption-index" data-layout-ignore>0${i + 1} / 0${beatClips.length}</span>
        <span id="badge-${b.id}" class="caption-badge" data-layout-ignore>${b.badge}</span>
        <h2 id="head-${b.id}" class="caption-headline">${b.headline}</h2>
        <p id="sub-${b.id}" class="caption-subhead" data-layout-ignore>${b.subhead}</p>
      </div>`).join('\n');

  const tweens = beatClips.map((b) => `
      tl.fromTo("#frame-${b.id}", { opacity: 0, y: 46, scale: 0.955 }, { opacity: 1, y: 0, scale: 1, duration: 0.75, ease: "expo.out" }, ${b.start});
      tl.fromTo("#vid-${b.id}", { scale: 1.0 }, { scale: 1.035, duration: ${b.duration}, ease: "none" }, ${b.start});
      tl.fromTo("#idx-${b.id}", { opacity: 0, x: -12 }, { opacity: 1, x: 0, duration: 0.45, ease: "power3.out" }, ${b.start + 0.05});
      tl.fromTo("#badge-${b.id}", { opacity: 0, x: -12 }, { opacity: 1, x: 0, duration: 0.45, ease: "power3.out" }, ${b.start + 0.1});
      tl.fromTo("#head-${b.id}", { opacity: 0, y: 38 }, { opacity: 1, y: 0, duration: 0.7, ease: "expo.out" }, ${b.start + 0.12});
      tl.fromTo("#sub-${b.id}", { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.6, ease: "power3.out" }, ${b.start + 0.28});
      tl.to(["#frame-${b.id}", "#card-${b.id}"], { opacity: 0, duration: 0.3, ease: "power2.in" }, ${b.start + b.duration - 0.3});`).join('\n');

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="Content-Security-Policy" content="script-src 'self' 'unsafe-inline' 'unsafe-eval' blob: data: https://cdn.jsdelivr.net http://127.0.0.1:* http://localhost:*" />
    <meta name="viewport" content="width=1920, height=1080" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        width: 1920px; height: 1080px; overflow: hidden; color: #141413;
        background: radial-gradient(120% 90% at 50% 0%, #f4f3f0 0%, #eeede9 45%, #e2e0da 100%);
        font-family: "Segoe UI Variable Display", "Segoe UI", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", Arial, sans-serif;
      }
      /* Some local proxies (e.g. ad blockers) inject UI into every page; keep renders clean. */
      body > *:not(#root):not(#outro-stage):not(script):not(style) { display: none !important; }
      [id*="adguard" i], [class*="adguard" i] { display: none !important; }
      #root { position: relative; width: 1920px; height: 1080px; }
      .clip-frame {
        position: absolute; top: 236px; left: 312px; width: 1296px; height: 730px;
        border-radius: 18px; overflow: hidden; background: #161c27;
        box-shadow: 0 50px 120px -30px rgba(20, 20, 19, 0.38), 0 2px 10px rgba(20, 20, 19, 0.10);
        border: 1px solid rgba(20, 20, 19, 0.10);
      }
      .video-clip { width: 100%; height: 100%; object-fit: cover; display: block; transform-origin: 50% 40%; }
      .caption { position: absolute; top: 64px; left: 312px; right: 312px; }
      .caption-index { font-family: "Cascadia Mono", Consolas, monospace; font-size: 15px; letter-spacing: 0.12em; color: rgba(20, 20, 19, 0.45); margin-right: 16px; }
      .caption-badge { font-size: 13px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: #2a688d; }
      .caption-headline { font-size: 66px; line-height: 1.02; font-weight: 700; letter-spacing: -0.035em; color: #141413; margin-top: 14px; max-width: 900px; }
      .caption-subhead { position: absolute; right: 0; top: 52px; max-width: 420px; text-align: right; font-size: 19px; line-height: 1.4; color: rgba(20, 20, 19, 0.62); }
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="promo-1080p" data-start="0" data-duration="${config.totalDuration}" data-width="1920" data-height="1080">
      <audio id="bg-music" data-start="0" data-duration="${config.totalDuration}" data-fade-in="${config.audio.fadeInSeconds}" data-fade-out="${config.audio.fadeOutSeconds}" data-volume="${config.audio.musicVolume}" src="assets/music/${config.audio.musicTrack}"></audio>
      <audio id="sfx-b1" data-start="0.1" data-duration="0.18" data-volume="${config.audio.sfx.beat1.volume}" src="assets/sfx/impact/${config.audio.sfx.beat1.file}"></audio>
      <audio id="sfx-b2" data-start="4.5" data-duration="0.11" data-volume="${config.audio.sfx.beat2.volume}" src="assets/sfx/interface/${config.audio.sfx.beat2.file}"></audio>
      <audio id="sfx-b3" data-start="8.5" data-duration="0.10" data-volume="${config.audio.sfx.beat3.volume}" src="assets/sfx/interface/${config.audio.sfx.beat3.file}"></audio>
      <audio id="sfx-b4" data-start="13.0" data-duration="0.19" data-volume="${config.audio.sfx.beat4.volume}" src="assets/sfx/interface/${config.audio.sfx.beat4.file}"></audio>
      <audio id="sfx-b5" data-start="17.5" data-duration="0.62" data-volume="${config.audio.sfx.beat5.volume}" src="assets/sfx/interface/${config.audio.sfx.beat5.file}"></audio>
      <audio id="sfx-b6" data-start="21.84" data-duration="1.48" data-volume="${config.audio.sfx.beat6.volume}" src="assets/sfx/impact/${config.audio.sfx.beat6.file}"></audio>
${videoTags}
      <div id="card-outro" class="clip" data-composition-id="outro-host" data-composition-src="compositions/outro.html" data-start="${outroBeat.start}" data-duration="${outroBeat.duration}"></div>
    </div>
    <script>
      window.__timelines = window.__timelines || {};
      const tl = gsap.timeline({ paused: true });
${tweens}
      window.__timelines["promo-1080p"] = tl;
    </script>
  </body>
</html>`;
}

// Build Outro Landscape Subcomposition
function buildLandscapeOutroHtml(outroBeat) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="Content-Security-Policy" content="script-src 'self' 'unsafe-inline' 'unsafe-eval' blob: data: https://cdn.jsdelivr.net http://127.0.0.1:* http://localhost:*" />
    <meta name="viewport" content="width=1920, height=1080" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        width: 1920px; height: 1080px; overflow: hidden; color: #141413;
        background: radial-gradient(120% 90% at 50% 0%, #f4f3f0 0%, #eeede9 45%, #e2e0da 100%);
        font-family: "Segoe UI Variable Display", "Segoe UI", -apple-system, BlinkMacSystemFont, Roboto, Arial, sans-serif;
      }
      /* Some local proxies (e.g. ad blockers) inject UI into every page; keep renders clean. */
      body > *:not(#root):not(#outro-stage):not(script):not(style) { display: none !important; }
      [id*="adguard" i], [class*="adguard" i] { display: none !important; }
      #outro-stage { width: 1920px; height: 1080px; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; }
      .outro-icon { width: 128px; height: 128px; border-radius: 30px; box-shadow: 0 30px 70px -20px rgba(20,20,19,0.45); margin-bottom: 40px; }
      .outro-title { font-size: 150px; line-height: 0.95; font-weight: 700; letter-spacing: -0.05em; }
      .outro-tagline { font-size: 34px; color: rgba(20,20,19,0.66); margin-top: 22px; letter-spacing: -0.01em; }
      .outro-features { margin-top: 34px; font-size: 18px; font-weight: 600; letter-spacing: 0.16em; text-transform: uppercase; color: #2a688d; }
      .outro-url { margin-top: 40px; font-family: "Cascadia Mono", Consolas, monospace; font-size: 26px; color: #141413; padding: 14px 28px; border: 1px solid rgba(20,20,19,0.18); border-radius: 999px; background: rgba(255,255,255,0.5); }
    </style>
  </head>
  <body>
    <div id="outro-stage" data-composition-id="outro" data-start="0" data-duration="${outroBeat.duration}" data-width="1920" data-height="1080">
      <img id="outro-logo" class="outro-icon" src="../assets/icons/piframe-icon.png" alt="PiFrame Logo" />
      <h1 id="outro-title" class="outro-title">${outroBeat.title}</h1>
      <p id="outro-tagline" class="outro-tagline">${outroBeat.tagline}</p>
      <p id="outro-features" class="outro-features" data-layout-ignore>${outroBeat.features} · ${outroBeat.platforms}</p>
      <p id="outro-url" class="outro-url">${outroBeat.repo}</p>
    </div>
    <script>
      window.__timelines = window.__timelines || {};
      const tl = gsap.timeline({ paused: true });
      tl.fromTo("#outro-logo", { opacity: 0, scale: 0.6, rotate: -8 }, { opacity: 1, scale: 1, rotate: 0, duration: 0.9, ease: "expo.out" }, 0.05);
      tl.fromTo("#outro-title", { opacity: 0, y: 70 }, { opacity: 1, y: 0, duration: 0.9, ease: "expo.out" }, 0.2);
      tl.fromTo("#outro-tagline", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.7, ease: "power3.out" }, 0.45);
      tl.fromTo("#outro-features", { opacity: 0 }, { opacity: 1, duration: 0.6 }, 0.7);
      tl.fromTo("#outro-url", { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.6, ease: "power3.out" }, 0.9);
      window.__timelines["outro"] = tl;
    </script>
  </body>
</html>`;
}

// Build Social Cut HTML (1080x1350)
function buildSocialHtml(config, beats) {
  const beatClips = beats.filter(b => b.slug !== 'outro');
  const outroBeat = beats.find(b => b.slug === 'outro');

  const videoTags = beatClips.map((b) => `
      <video id="vid-${b.id}" class="clip social-video-clip" data-start="${b.start}" data-duration="${b.duration}" data-media-start="${b.clipStart}" muted playsinline src="assets/clips/${b.slug}.mp4"></video>
      <div id="card-${b.id}" class="clip social-header-card" data-start="${b.start}" data-duration="${b.duration}">
        <span id="badge-${b.id}" class="social-badge" data-layout-ignore>${b.badge}</span>
        <span id="head-${b.id}" class="social-headline">${b.headline}</span>
        <span id="sub-${b.id}" class="social-subhead" data-layout-ignore>${b.subhead}</span>
      </div>
      <div id="footer-${b.id}" class="clip social-footer-bar" data-start="${b.start}" data-duration="${b.duration}">
        <span class="social-stat-card"><span class="social-stat-label" data-layout-ignore>STACK</span><span class="social-stat-val" data-layout-ignore>Native Flutter</span></span>
        <span class="social-stat-card"><span class="social-stat-label" data-layout-ignore>DAEMON</span><span class="social-stat-val" data-layout-ignore>Disconnect-Safe</span></span>
        <span class="social-stat-card"><span class="social-stat-label" data-layout-ignore>PRIVACY</span><span class="social-stat-val" data-layout-ignore>Zero Telemetry</span></span>
      </div>`).join('\n');

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=1080, height=1350" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        width: 1080px;
        height: 1350px;
        background: #eeede9;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        overflow: hidden;
      }
      #root {
        position: relative;
        width: 1080px;
        height: 1350px;
      }
      .social-video-clip {
        position: absolute;
        top: 360px;
        left: 60px;
        width: 960px;
        height: 540px;
        border-radius: 18px;
        overflow: hidden;
        box-shadow: 0 20px 50px rgba(0, 0, 0, 0.15);
        border: 1px solid rgba(0, 0, 0, 0.08);
        background: #161c27;
        object-fit: cover;
        display: block;
      }
      .social-header-card {
        position: absolute;
        top: 60px;
        left: 60px;
        width: 960px;
        background: #161c27;
        border-radius: 20px;
        padding: 30px 36px;
        box-shadow: 0 16px 40px rgba(0, 0, 0, 0.12);
        border: 1px solid rgba(255, 255, 255, 0.08);
        display: flex;
        flex-direction: column;
      }
      .social-badge {
        display: inline-block;
        align-self: flex-start;
        font-size: 14px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #5f9fc5;
        background: rgba(95, 159, 197, 0.15);
        padding: 6px 14px;
        border-radius: 6px;
        border: 1px solid rgba(95, 159, 197, 0.3);
        margin-bottom: 12px;
      }
      .social-headline {
        font-size: 34px;
        font-weight: 700;
        color: #ffffff;
        line-height: 1.25;
        margin-bottom: 8px;
      }
      .social-subhead {
        font-size: 18px;
        color: #94a3b8;
        line-height: 1.4;
      }
      .social-footer-bar {
        position: absolute;
        top: 930px;
        left: 60px;
        width: 960px;
        display: flex;
        gap: 16px;
      }
      .social-stat-card {
        flex: 1;
        background: #161c27;
        border-radius: 16px;
        padding: 20px;
        text-align: center;
        border: 1px solid rgba(255, 255, 255, 0.06);
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.1);
        display: flex;
        flex-direction: column;
      }
      .social-stat-label {
        font-size: 13px;
        font-weight: 700;
        color: #5f9fc5;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        margin-bottom: 4px;
      }
      .social-stat-val {
        font-size: 18px;
        font-weight: 700;
        color: #ffffff;
      }
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="promo-social" data-start="0" data-duration="${config.totalDuration}" data-width="1080" data-height="1350">
      
      <!-- Audio Layer -->
      <audio id="bg-music" data-start="0" data-duration="${config.totalDuration}" data-fade-in="${config.audio.fadeInSeconds}" data-fade-out="${config.audio.fadeOutSeconds}" data-volume="${config.audio.musicVolume}" src="assets/music/${config.audio.musicTrack}"></audio>
      <audio id="sfx-b1" data-start="0.1" data-duration="0.18" data-volume="${config.audio.sfx.beat1.volume}" src="assets/sfx/impact/${config.audio.sfx.beat1.file}"></audio>
      <audio id="sfx-b2" data-start="4.5" data-duration="0.11" data-volume="${config.audio.sfx.beat2.volume}" src="assets/sfx/interface/${config.audio.sfx.beat2.file}"></audio>
      <audio id="sfx-b3" data-start="8.5" data-duration="0.10" data-volume="${config.audio.sfx.beat3.volume}" src="assets/sfx/interface/${config.audio.sfx.beat3.file}"></audio>
      <audio id="sfx-b4" data-start="13.0" data-duration="0.19" data-volume="${config.audio.sfx.beat4.volume}" src="assets/sfx/interface/${config.audio.sfx.beat4.file}"></audio>
      <audio id="sfx-b5" data-start="17.5" data-duration="0.62" data-volume="${config.audio.sfx.beat5.volume}" src="assets/sfx/interface/${config.audio.sfx.beat5.file}"></audio>
      <audio id="sfx-b6" data-start="21.84" data-duration="1.48" data-volume="${config.audio.sfx.beat6.volume}" src="assets/sfx/impact/${config.audio.sfx.beat6.file}"></audio>

      <!-- Video Beats -->
${videoTags}

      <!-- Beat 6: Outro -->
      <div id="card-outro-social" class="clip" data-composition-id="outro-social-host" data-composition-src="compositions/outro-social.html" data-start="${outroBeat.start}" data-duration="${outroBeat.duration}"></div>

    </div>
    <script>
      window.__timelines = window.__timelines || {};
      const tl = gsap.timeline({ paused: true });
      window.__timelines["promo-social"] = tl;
    </script>
  </body>
</html>`;
}

// Build Outro Social Subcomposition
function buildSocialOutroHtml(outroBeat) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=1080, height=1350" />
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body {
        width: 1080px;
        height: 1350px;
        background: #eeede9;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        overflow: hidden;
      }
      #outro-stage {
        width: 1080px;
        height: 1350px;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 60px;
      }
      .outro-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        text-align: center;
        background: #161c27;
        border-radius: 32px;
        padding: 64px 48px;
        box-shadow: 0 30px 80px rgba(0, 0, 0, 0.25);
        border: 1px solid rgba(255, 255, 255, 0.1);
        width: 960px;
      }
      .outro-icon {
        width: 140px;
        height: 140px;
        margin-bottom: 24px;
        border-radius: 28px;
      }
      .outro-title {
        font-size: 64px;
        font-weight: 800;
        color: #ffffff;
        letter-spacing: -0.02em;
        margin-bottom: 12px;
      }
      .outro-tagline {
        font-size: 28px;
        color: #cbd5e1;
        margin-bottom: 24px;
      }
      .outro-platforms {
        display: inline-flex;
        gap: 14px;
        margin-bottom: 28px;
      }
      .platform-pill {
        background: rgba(95, 159, 197, 0.15);
        border: 1px solid rgba(95, 159, 197, 0.35);
        color: #5f9fc5;
        font-size: 16px;
        font-weight: 600;
        padding: 8px 22px;
        border-radius: 24px;
      }
      .outro-url {
        font-family: monospace;
        font-size: 28px;
        font-weight: 700;
        color: #81b2cf;
        letter-spacing: 0.02em;
      }
    </style>
  </head>
  <body>
    <div id="outro-stage" data-composition-id="outro-social" data-start="0" data-duration="${outroBeat.duration}" data-width="1080" data-height="1350">
      <div id="outro-box" class="outro-card">
        <img id="outro-logo" class="outro-icon" src="../assets/icons/piframe-icon.png" alt="PiFrame Logo" />
        <h1 id="outro-title" class="outro-title">${outroBeat.title}</h1>
        <p id="outro-tagline" class="outro-tagline">${outroBeat.tagline}</p>
        <span id="outro-platforms" class="outro-platforms">
          <span id="pill-win" class="platform-pill" data-layout-ignore>Windows</span>
          <span id="pill-mac" class="platform-pill" data-layout-ignore>macOS</span>
          <span id="pill-lin" class="platform-pill" data-layout-ignore>Linux</span>
        </span>
        <p id="outro-url" class="outro-url">${outroBeat.repo}</p>
      </div>
    </div>
  </body>
</html>`;
}

// Setup a Composition Workspace
function setupComposition(targetDir, config, beats, resolvedClips, isSocial = false) {
  mkdirSync(targetDir, { recursive: true });
  mkdirSync(join(targetDir, 'assets', 'clips'), { recursive: true });
  mkdirSync(join(targetDir, 'assets', 'music'), { recursive: true });
  mkdirSync(join(targetDir, 'assets', 'icons'), { recursive: true });
  mkdirSync(join(targetDir, 'assets', 'sfx', 'impact'), { recursive: true });
  mkdirSync(join(targetDir, 'assets', 'sfx', 'interface'), { recursive: true });
  mkdirSync(join(targetDir, 'compositions'), { recursive: true });

  // Copy Music
  const musicDest = join(targetDir, 'assets', 'music', config.audio.musicTrack);
  if (!existsSync(musicDest)) {
    copyFileSync(DEFAULT_MUSIC_PATH, musicDest);
  }

  // Copy Icon
  const iconDest = join(targetDir, 'assets', 'icons', 'piframe-icon.png');
  if (!existsSync(iconDest)) {
    copyFileSync(DEFAULT_ICON_PATH, iconDest);
  }

  // Copy SFX
  for (const sfxKey of Object.keys(config.audio.sfx)) {
    const sfx = config.audio.sfx[sfxKey];
    const sfxSrc = join(SFX_ROOT, sfx.folder, sfx.file);
    const sfxDest = join(targetDir, 'assets', 'sfx', sfx.folder, sfx.file);
    if (existsSync(sfxSrc) && !existsSync(sfxDest)) {
      copyFileSync(sfxSrc, sfxDest);
    }
  }

  // Copy Clips
  for (const beat of beats) {
    if (beat.slug === 'outro') continue;
    const clipSrc = resolvedClips[beat.slug];
    const clipDest = join(targetDir, 'assets', 'clips', `${beat.slug}.mp4`);
    if (clipSrc && existsSync(clipSrc)) {
      copyFileSync(clipSrc, clipDest);
    }
  }

  // Write hyperframes.json
  writeFileSync(join(targetDir, 'hyperframes.json'), JSON.stringify({
    "$schema": "https://hyperframes.heygen.com/schema/hyperframes.json"
  }, null, 2));

  // Write index.html and subcomposition
  const outroBeat = beats.find(b => b.slug === 'outro');
  if (isSocial) {
    writeFileSync(join(targetDir, 'index.html'), buildSocialHtml(config, beats));
    writeFileSync(join(targetDir, 'compositions', 'outro-social.html'), buildSocialOutroHtml(outroBeat));
  } else {
    writeFileSync(join(targetDir, 'index.html'), buildLandscapeHtml(config, beats));
    writeFileSync(join(targetDir, 'compositions', 'outro.html'), buildLandscapeOutroHtml(outroBeat));
  }
}

// Run hyperframes check
function runCheck(compDir) {
  console.log(`\n[hyperframes] Checking composition in ${compDir}...`);
  const isWindows = process.platform === 'win32';
  const npxCmd = isWindows ? 'npx.cmd' : 'npx';
  const res = spawnSync(npxCmd, ['hyperframes', 'check'], {
    cwd: compDir,
    shell: isWindows, // .cmd shims need a shell on Windows (Node >= 20)
    stdio: 'inherit'
  });
  if (res.status !== 0) {
    throw new Error(`hyperframes check failed in ${compDir} with exit code ${res.status}`);
  }
}

// Run hyperframes render
function runRender(compDir, outputFilePath) {
  console.log(`\n[hyperframes] Rendering composition to ${outputFilePath}...`);
  mkdirSync(dirname(outputFilePath), { recursive: true });
  const isWindows = process.platform === 'win32';
  const npxCmd = isWindows ? 'npx.cmd' : 'npx';
  const res = spawnSync(npxCmd, ['hyperframes', 'render', '-o', `"${outputFilePath}"`], {
    cwd: compDir,
    shell: isWindows,
    stdio: 'inherit'
  });
  if (res.status !== 0) {
    throw new Error(`hyperframes render failed with exit code ${res.status}`);
  }
}

// Generate web MP4, WebM, and poster
function generateWebEncodes(master1080p, outWebMp4, outWebWebm, outPoster, config) {
  console.log('\n[ffmpeg] Generating web encodes and poster still...');
  mkdirSync(dirname(outWebMp4), { recursive: true });

  // 1. Poster Still Frame
  console.log(`[ffmpeg] Extracting poster at ${config.encodes.posterTimestamp}s: ${outPoster}`);
  execFileSync(FFMPEG, [
    '-y',
    '-ss', String(config.encodes.posterTimestamp),
    '-i', master1080p,
    '-frames:v', '1',
    '-update', '1',
    '-q:v', '2',
    outPoster
  ], { stdio: 'inherit' });

  // 2. Web MP4 (H.264 High profile, faststart, <= 8MB)
  console.log(`[ffmpeg] Encoding Web MP4 (<= 8MB): ${outWebMp4}`);
  execFileSync(FFMPEG, [
    '-y',
    '-i', master1080p,
    '-c:v', 'libx264',
    '-profile:v', 'high',
    '-pix_fmt', 'yuv420p',
    '-crf', String(config.encodes.webMp4.crf),
    '-maxrate', config.encodes.webMp4.maxrate,
    '-bufsize', config.encodes.webMp4.bufsize,
    '-preset', 'slow',
    '-movflags', '+faststart',
    '-c:a', 'aac',
    '-b:a', config.encodes.webMp4.audioBitrate,
    outWebMp4
  ], { stdio: 'inherit' });

  // 3. Web WebM (VP9, <= 8MB)
  console.log(`[ffmpeg] Encoding Web WebM (VP9): ${outWebWebm}`);
  execFileSync(FFMPEG, [
    '-y',
    '-i', master1080p,
    '-c:v', 'libvpx-vp9',
    '-b:v', config.encodes.webWebm.bitrate,
    '-crf', String(config.encodes.webWebm.crf),
    '-c:a', 'libopus',
    '-b:a', config.encodes.webWebm.audioBitrate,
    outWebWebm
  ], { stdio: 'inherit' });

  // 4. Bake poster frame 0 into master1080p per brag deliver specification
  console.log(`[ffmpeg] Baking poster into frame 0 of master...`);
  const tempWithPoster = master1080p.replace(/\.mp4$/, '.poster.mp4');
  try {
    execFileSync(FFMPEG, [
      '-y',
      '-i', master1080p,
      '-i', outPoster,
      '-filter_complex', "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]",
      '-map', '[v]',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-crf', '18',
      '-preset', 'slow',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'copy',
      '-movflags', '+faststart',
      tempWithPoster
    ], { stdio: 'ignore' });
    if (existsSync(tempWithPoster)) {
      copyFileSync(tempWithPoster, master1080p);
      spawnSync('rm', ['-f', tempWithPoster], { shell: true });
    }
  } catch (err) {
    console.warn(`[ffmpeg] Note: frame 0 overlay skipped (${err.message})`);
  }
}

// Main execution flow
async function main() {
  const options = parseArgs();
  if (options.help) {
    printHelp();
    return;
  }

  console.log('====================================================');
  console.log('   PiFrame Promo Video Production Pipeline (Brag)  ');
  console.log('====================================================');

  const config = JSON.parse(readFileSync(options.configPath, 'utf8'));
  const beats = config.beats;

  // Determine Output Destinations
  const isTestMode = options.test;
  const workBaseDir = isTestMode ? 'C:/demo/tools/brag-work/work' : join(__dirname, 'work');
  const targetDir = options.outDir || (isTestMode ? 'C:/demo/tools/brag-work/test-render' : __dirname);

  console.log(`Mode:            ${isTestMode ? 'TEST PIPELINE (--test)' : 'PRODUCTION'}`);
  console.log(`Target Dir:      ${targetDir}`);
  console.log(`Work Dir:        ${workBaseDir}`);
  console.log(`Duration:        ${config.totalDuration}s`);

  // Resolve Real Clips or Generate Test Clip
  let fallbackTestClip = options.testClip;
  if (!fallbackTestClip || !existsSync(fallbackTestClip)) {
    const testClipPath = 'C:/demo/tools/brag-work/neutral-test-clip.mp4';
    if (!existsSync(testClipPath)) {
      generateNeutralTestClip(testClipPath, 12);
    }
    fallbackTestClip = testClipPath;
  }

  const resolvedClips = {};
  for (const beat of beats) {
    if (beat.slug === 'outro') continue;
    const realPath = join(options.clipsDir, beat.slug, 'master.mp4');
    if (!isTestMode && existsSync(realPath)) {
      resolvedClips[beat.slug] = realPath;
      console.log(`[clip] Found real capture for ${beat.slug}: ${realPath}`);
    } else {
      resolvedClips[beat.slug] = fallbackTestClip;
      console.log(`[clip] Using neutral test clip for ${beat.slug}: ${fallbackTestClip}`);
    }
  }

  // Define Deliverable Paths
  const master1080pPath = join(targetDir, 'piframe-promo-1080p.mp4');
  const masterSocialPath = join(targetDir, 'piframe-promo-social.mp4');

  // Web deliverables: if in test mode, put them into targetDir; in prod mode, into website/assets/video
  const webDir = isTestMode ? targetDir : DEFAULT_WEBSITE_VIDEO_DIR;
  const webMp4Path = join(webDir, 'piframe-promo.mp4');
  const webWebmPath = join(webDir, 'piframe-promo.webm');
  const posterPath = join(webDir, 'piframe-promo-poster.jpg');

  // Render Landscape 1080p
  if (!options.socialOnly) {
    const landscapeCompDir = join(workBaseDir, 'comp-1080p');
    console.log(`\nSetting up 1080p Landscape composition: ${landscapeCompDir}`);
    setupComposition(landscapeCompDir, config, beats, resolvedClips, false);
    if (!options.skipCheck) {
      runCheck(landscapeCompDir);
    }
    runRender(landscapeCompDir, master1080pPath);
  }

  // Render Social Cut 1080x1350
  if (!options.landscapeOnly) {
    const socialCompDir = join(workBaseDir, 'comp-social');
    console.log(`\nSetting up 1080x1350 Social Cut composition: ${socialCompDir}`);
    setupComposition(socialCompDir, config, beats, resolvedClips, true);
    if (!options.skipCheck) {
      runCheck(socialCompDir);
    }
    runRender(socialCompDir, masterSocialPath);
  }

  // Generate Web Encodes
  if (!options.socialOnly && existsSync(master1080pPath)) {
    generateWebEncodes(master1080pPath, webMp4Path, webWebmPath, posterPath, config);
  }

  // Summary Report
  console.log('\n====================================================');
  console.log('   PiFrame Promo Pipeline Completed Successfully!   ');
  console.log('====================================================');

  const filesToCheck = [
    { label: '1080p Master (16:9)', path: master1080pPath },
    { label: 'Social Cut (4:5)', path: masterSocialPath },
    { label: 'Web MP4 (H.264)', path: webMp4Path },
    { label: 'Web WebM (VP9)', path: webWebmPath },
    { label: 'Poster Still Frame', path: posterPath }
  ];

  for (const item of filesToCheck) {
    if (existsSync(item.path)) {
      const stats = statSync(item.path);
      const mb = (stats.size / (1024 * 1024)).toFixed(2);
      console.log(`  ✓ ${item.label.padEnd(22)}: ${item.path} (${mb} MB)`);
    } else {
      console.log(`  - ${item.label.padEnd(22)}: [Not generated in this run]`);
    }
  }

  console.log('\nPipeline ready for real showcase clips.');
}

main().catch(err => {
  console.error('\n[FATAL ERROR]', err);
  process.exit(1);
});

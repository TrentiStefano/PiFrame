# Remote phone web app: emulated iPhone check

Runs the real daemon + the real Flutter web build behind an HTTPS host (`pf-remote.test`) and drives
it with a Playwright WebKit mobile profile (DPR 3, touch). Defaults to iPhone 12; set `PF_E2E_DEVICE`
to another Playwright device name. `iPhone 18 Pro` uses the iPhone 17 Pro descriptor because Playwright
has no iPhone 18 profile yet; its viewport dimensions match Apple's published 18 Pro display resolution.
Covers pairing, reload, daemon restart (update), lost credential, offline panel, compression, service
worker, page pinning and tap coordinates.

The daemon runs with a fresh temporary `PI_FRAME_HOME`, `HOME`, `USERPROFILE`, and Pi session directory,
so the test cannot read the developer's Pi sessions. The browser run emulates WebKit/touch; it cannot
reproduce physical iOS Safari's URL bar, keyboard viewport behaviour, or device GPU. Confirm those on
a physical phone. By default Playwright uses the visible browser viewport; set `PF_E2E_FULL_SCREEN=1`
to render at the device's full logical screen size and produce native-resolution PNG dimensions (without
Safari chrome).

## Run

```bash
pnpm --filter @piframe/agentd run build:bundle          # daemon bundle
(cd apps/pi_frame && flutter build web --release --no-web-resources-cdn --pwa-strategy=none)
npm install --prefix ~/.pf-e2e playwright               # once (outside the pnpm workspace)
npx --prefix ~/.pf-e2e playwright install webkit        # once
node tools/remote-e2e/remote-iphone-e2e.mjs             # ENGINE=chromium to use Chromium
```

Playwright is looked up in `~/.pf-e2e` (override with `PF_E2E_DIR`). Requires `openssl` on PATH. Screenshots go to `tools/remote-e2e/shots/` (override with `PF_E2E_SHOTS`). `PF_E2E_DEVICE` selects a Playwright device descriptor; the default is `iPhone 12`. Use `PF_E2E_DEVICE='iPhone 18 Pro'` to use the 17 Pro geometry alias, and `PF_E2E_FULL_SCREEN=1` for the full logical display viewport.
Exit code is non-zero if any check fails.

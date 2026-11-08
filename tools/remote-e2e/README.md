# Remote phone web app: emulated iPhone check

Runs the real daemon + the real Flutter web build behind an HTTPS host (`pf-remote.test`) and drives
it with an iPhone 12 profile (WebKit, DPR 3, touch). Covers pairing, reload, daemon restart (update),
lost credential, offline panel, compression, service worker, page pinning and tap coordinates.

It cannot reproduce iOS Safari's URL bar / keyboard viewport behaviour or the A14 GPU: confirm those
on a physical phone.

## Run

```bash
pnpm --filter @piframe/agentd run build:bundle          # daemon bundle
(cd apps/pi_frame && flutter build web --release --no-web-resources-cdn --pwa-strategy=none)
npm install --prefix ~/.pf-e2e playwright               # once (outside the pnpm workspace)
npx --prefix ~/.pf-e2e playwright install webkit        # once
node tools/remote-e2e/remote-iphone-e2e.mjs             # ENGINE=chromium to use Chromium
```

Playwright is looked up in `~/.pf-e2e` (override with `PF_E2E_DIR`). Requires `openssl` on PATH. Screenshots go to `tools/remote-e2e/shots/` (override with `PF_E2E_SHOTS`).
Exit code is non-zero if any check fails.

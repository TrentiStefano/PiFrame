# Mobile web screenshots

Real screenshots from PiFrame's Flutter Web app, reached through the remote-pairing HTTPS flow. Both runs use Playwright WebKit emulation with touch; they do not capture or emulate a physical iPhone's complete Safari chrome/GPU.

## Profiles

Each device folder has two captures of the same states:

- `full-screen/` renders the app at the device's full logical screen size, so PNG dimensions match native pixels: [iPhone 12](iphone-12/full-screen/) is 390×844 CSS at DPR 3 → 1170×2532; [iPhone 18 Pro profile](iphone-18/full-screen/) is 402×874 CSS at DPR 3 → 1206×2622. This uses a full-screen page viewport with touch enabled and no Safari browser chrome.
- `viewport/` preserves Playwright's browser-visible viewport profile, which excludes simulated Safari chrome: [iPhone 12](iphone-12/viewport/) is 390×664 CSS → 1170×1992; [iPhone 18 Pro profile](iphone-18/viewport/) is 402×681 CSS → 1206×2043.

Playwright has no iPhone 18 descriptor, so the iPhone 18 Pro profile uses its iPhone 17 Pro WebKit descriptor. Apple publishes the 18 Pro display as 2622×1206; the logical screen geometry matches 402×874 points at 3×. The emulated user-agent remains the Playwright 17 Pro UA.

## Captured states

Both folders have matching `A`, `B`, `B1`–`B9`, `D`, `E`, and `G` screenshots:

- unpaired and paired welcome
- new-session dialog, selected working directory, active workspace
- composer draft and fake-pi response
- sessions drawer, Settings, File, and Git Changes panes
- daemon restart, touch alignment, offline panel

The mobile E2E run passed 16/16 checks for both profiles. It used temporary `PI_FRAME_HOME`, `HOME`, `USERPROFILE`, Pi agent/session directories, and a fake Git workspace with fake-pi. No user's Pi session data was used. `E-after-taps.png` shows the new-session field focused after the touch-coordinate probe; it is close to `B1` but records the focus state.

For routes, responsive breakpoints, and details of what each image shows, see [`../NAVIGATION-MAP.md`](../NAVIGATION-MAP.md).

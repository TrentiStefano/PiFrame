---
name: piframe-ui-preview
description: Show a real PiFrame UI screenshot. Use when the user asks to see, preview, or show a screenshot of a PiFrame feature, screen, dialog, theme, or layout.
---

# PiFrame UI preview

Show the actual Flutter app. Never fabricate or mock PiFrame UI.

1. Run `pnpm harness status` from the repository root. Reuse a live run; otherwise start one with `pnpm harness start [--scenario <name>] [--size <WxH>]`.
2. Use `pnpm harness tree` to find stable selectors. Navigate to the requested feature with the fewest actions. Use `tap`, `type`, `key`, `hover`, and `scroll` as needed. Set the requested size with `pnpm harness resize <WxH>` and choose a requested theme through the app UI.
3. Capture with `pnpm harness shot <descriptive-label>`.
4. Read the PNG and verify it shows the requested feature, screen, dialog, theme, or layout. If it does not, adjust the app and capture again.
5. Report the screenshot in chat with the actual absolute file path returned by the harness, using this format, plus one concise line explaining how you reached it:

   `![<label>](<absolute path>)`

6. Stop the harness with `pnpm harness stop` unless the user is iterating on the preview.

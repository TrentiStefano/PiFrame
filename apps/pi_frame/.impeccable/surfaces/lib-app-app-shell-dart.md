---
version: 2
slug: "lib-app-app-shell-dart"
primary_target: "lib/app/app_shell.dart"
related_targets: ["lib/main.dart","lib/ui/precision.dart","lib/app/desktop_chrome.dart","lib/features/transcript/transcript_view.dart","lib/features/composer/composer.dart"]
---

# PiFrame — Bento Workbench

Current app-shell contract. Root `DESIGN.md` is authoritative.

## Direction contract

**Thesis:** A coherent, local-first Pi workbench. Bento describes repository/editor, chat and Git Changes spatial grouping; shared surface grammar applies beyond panes.

**Palette:** Official Catppuccin Latte and Frappé values from `themes/piframe-*.json`, mirrored in Flutter assets and token fallbacks. Mauve is the primary accent; Green/Yellow/Red/Blue are semantic status roles. Never use custom darkened/shifted hues. Small text uses named palette text colors; accents appear on icons, borders and tinted surfaces.

**Surfaces:** Use modest rounded corners and subtle 1px borders for functional UI throughout: app sections, session rows, transcript/tool/code blocks, composer, settings, inputs, dialogs and menus. Keep list density high; don't card every text row. No square borderless controls, deep shadows, glass or nested stacks.

**Identity and type:** Preserve PiFrame's own name and mark. Keep Barlow Condensed for identity/headings, Schibsted Grotesk for UI/body and Source Code Pro for code/paths.

**Interaction:** Preserve session history ownership, local daemon boundary, drafts, queues, read-only safeguards and extension UI. Caption controls stay native and accessible. Keyboard actions remain immediate; reduced motion respected. Panes resize/hide without losing state.

## Evidence gate

Inspect fresh light/dark app renders, settings, session list, composer, transcript, dialogs, and wide/compact workspace. Test the theme selector against actual token colors and verify text contrast; do not claim visual QA from source alone.

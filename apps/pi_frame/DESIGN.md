---
name: PiFrame — Bento Workbench
description: "A coherent, local-first workbench for Pi sessions."
colors:
  latte-base: "#eff1f5"
  latte-mantle: "#e6e9ef"
  latte-surface0: "#ccd0da"
  latte-text: "#4c4f69"
  latte-mauve: "#8839ef"
  latte-green: "#40a02b"
  latte-yellow: "#df8e1d"
  latte-red: "#d20f39"
  frappe-base: "#303446"
  frappe-mantle: "#292c3c"
  frappe-surface0: "#414559"
  frappe-text: "#c6d0f5"
  frappe-mauve: "#ca9ee6"
  frappe-green: "#a6d189"
  frappe-yellow: "#e5c890"
  frappe-red: "#e78284"
rounded:
  sm: "6px"
  md: "10px"
  lg: "14px"
border:
  width: "1px"
  style: "subtle semantic border"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
---

# PiFrame — Bento Workbench

Root `DESIGN.md` is authoritative. This file records app-level implementation rules only.

## Product surface

PiFrame is a local-first Pi session workbench. Bento means three related work areas—repository/editor, Pi chat, and Git Changes—not a visual treatment reserved for those panes. Keep session identity and repository context visible; keep every write explicit and recoverable.

## Color

Use official Catppuccin Latte for light and Frappé for dark. Source of truth: `themes/piframe-light.json`, `themes/piframe-dark.json`, and matching bundled assets in `apps/pi_frame/assets/themes/`.

| Role | Latte | Frappé |
|---|---|---|
| Base | `#eff1f5` | `#303446` |
| Mantle | `#e6e9ef` | `#292c3c` |
| Surface 0 | `#ccd0da` | `#414559` |
| Text | `#4c4f69` | `#c6d0f5` |
| Mauve / primary accent | `#8839ef` | `#ca9ee6` |
| Green / success | `#40a02b` | `#a6d189` |
| Yellow / warning | `#df8e1d` | `#e5c890` |
| Red / danger | `#d20f39` | `#e78284` |

Do not darken or replace palette hues to make semantic colors pass as small text. Use named text colors for labels and accents for borders, icons or tinted state surfaces. Primary-action foreground/background pair must meet contrast requirements.

## Surface grammar

- Use a 1px Catppuccin border and modest radius on functional surfaces throughout the app: panes, settings sections, session rows, transcript/tool/code blocks, composer, inputs, dialogs and menus.
- Semantic radii: 6px small, 10px medium, 14px large. Keep Bento gutters narrow and content dense.
- Use surface contrast and alignment before elevation. No squared borderless cards, deep shadows, gradients, glass or decorative card stacks.
- Do not wrap every text row in a card; borders clarify meaningful controls and content groups.

## Typography and identity

Keep PiFrame's existing name, mark, and bundled typography. Barlow Condensed marks identity and headings; Schibsted Grotesk carries UI/body text; Source Code Pro is reserved strictly for paths, source and diffs. Repository file tree items MUST use Schibsted Grotesk (UI font), not monospace code font. Do not revive retired external styling references.

## Density & Activity Timeline

- **Intermediate chat activity**: Reasoning/thinking, tool calls, and command rows are rendered as compact, low-height summary rows (~26-28px) with status indicators and micro-typography (inspired by Antigravity), avoiding bloated cards. Clicking expands full details.
- **Scrollbar**: Transcript scrollbars omit background tracks (`trackVisibility: false`), showing only the thumb.
- **Chat alignment**: User messages are indented and offset to the right; agent turns align to the left.
- **Unified pane headers**: Repository, Git Changes, and Review Changes share the chat pane's subtle card top bar styling at a slimmer 38px profile.
- **App toolbar**: Compact 42px height with subtle branding wordmark (15px) and discrete icon buttons.
- **Composer**: Space-efficient layout with icon-only action buttons, model and thinking selectors located on the bottom-left row, and send/attach on the bottom-right.
- **Visual hierarchy & Color**: Colorful semantic Catppuccin file icons (`FileIcon`), syntax tokens, and git status counters (+added, -removed) provide clear scannability without the triple-tinted "AI-generated" look (colored fill + lighter outline + colored text).

## Interaction and adaptation

Keep Windows/macOS/Web at equal priority. Keyboard actions stay immediate. Preserve folder-scoped session creation, repository grouping, pane state, dirty buffers, safe Git operations, file/line context, and reduced-motion behavior across sizes. Root `DESIGN.md` defines complete interaction, accessibility and QA requirements.

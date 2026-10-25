---
name: PiFrame — Bento Workbench
description: "A coherent, local-first workbench for Pi sessions."
colors:
  piframe-dark-background: "#161c27"
  piframe-dark-chassis: "#121721"
  piframe-dark-surface: "#1c2432"
  piframe-dark-border: "#2e3c53"
  piframe-dark-text: "#f8fafc"
  piframe-dark-accent: "#5f9fc5"
  piframe-dark-success: "#a1d9b0"
  piframe-dark-warning: "#f6bd53"
  piframe-dark-danger: "#f1887a"
  piframe-light-background: "#f1f3f7"
  piframe-light-chassis: "#e6e9f0"
  piframe-light-surface: "#ffffff"
  piframe-light-border: "#d3dae4"
  piframe-light-text: "#0f172a"
  piframe-light-accent: "#24638a"
  piframe-light-success: "#336c42"
  piframe-light-warning: "#895706"
  piframe-light-danger: "#882316"
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

Use official PiFrame default themes: PiFrame Light for light mode and PiFrame Dark for dark mode. Source of truth: `themes/piframe-light.json`, `themes/piframe-dark.json`, and matching bundled assets in `apps/pi_frame/assets/themes/`.

| Role | PiFrame Light | PiFrame Dark |
|---|---|---|
| Background / Base | `#f1f3f7` | `#161c27` |
| Chassis / Mantle | `#e6e9f0` | `#121721` |
| Surface | `#ffffff` | `#1c2432` |
| Surface Elevated | `#ffffff` | `#242e40` |
| Display Surface | `#dae0ea` | `#242e40` |
| Display Text | `#0f172a` | `#f1f5f9` |
| Border | `#d3dae4` | `#2e3c53` |
| Border Strong | `#a3afc1` | `#475a77` |
| Text Primary | `#0f172a` | `#f8fafc` |
| Text Secondary | `#3d4a5c` | `#a3b2c5` |
| Text Muted | `#566376` | `#8696ab` |
| Accent (Steel Blue) | `#24638a` | `#5f9fc5` |
| Success | `#336c42` | `#a1d9b0` |
| Warning | `#895706` | `#f6bd53` |
| Danger | `#882316` | `#f1887a` |
| User Bubble | `#d3e3ef` | `#21344a` |
| Thinking / Working | `#436e89` | `#81b2cf` |

Do not darken or replace palette hues to make semantic colors pass as small text. Use named text colors for labels and accents for borders, icons or tinted state surfaces. Primary-action foreground/background pair must meet contrast requirements.

## Surface grammar

- Use a 1px subtle border and modest radius on functional surfaces throughout the app: panes, settings sections, session rows, transcript/tool/code blocks, composer, inputs, dialogs and menus.
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
- **Visual hierarchy & Color**: Colorful semantic file icons (`FileIcon`), syntax tokens, and git status counters (+added, -removed) provide clear scannability without the triple-tinted "AI-generated" look (colored fill + lighter outline + colored text).

## Interaction and adaptation

Keep Windows/macOS/Web at equal priority. Keyboard actions stay immediate. Preserve folder-scoped session creation, repository grouping, pane state, dirty buffers, safe Git operations, file/line context, and reduced-motion behavior across sizes. Root `DESIGN.md` defines complete interaction, accessibility and QA requirements.

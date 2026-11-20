# PiFrame Theming Guide

PiFrame has a theme engine based on JSON files (`version: 1`). It supports hot reload on desktop (every changed `.json` file is read again), inheritance through `extends`, and fault tolerance.

## Theme directories

PiFrame looks for themes in three places:
1. **Built-in themes (assets):** `piframe-dark.json`, `piframe-light.json`.
2. **Global user themes:** `~/.piframe/themes/*.json`.
3. **Workspace themes:** `<workspace>/.piframe/themes/*.json`.

PiFrame picks up themes created or changed in these directories without a restart.

## Minimal example with inheritance (`example-minimal.json`)

To make a variant of an existing theme, set `extends` to the ID of the base theme and list only the tokens you want to change:

```json
{
  "$schema": "https://pi-frame.dev/theme.schema.json",
  "schemaVersion": 1,
  "id": "amber-accent-dark",
  "name": "Amber Accent Dark",
  "author": "You",
  "version": "1.0.0",
  "variant": "dark",
  "extends": "piframe-dark",
  "colors": {
    "accent": "#FFB84D",
    "focusRing": "#FFB84D"
  }
}
```

Every token you do not set (backgrounds, surfaces, fonts, spacing, syntax colors and so on) comes from the parent theme `piframe-dark`.

## Validation and editor support

With `$schema: "https://pi-frame.dev/theme.schema.json"`, editors such as VS Code and other LSP-based IDEs give autocompletion, syntax validation and hints for every theme property. The schema ships with the app in `apps/pi_frame/assets/themes/theme.schema.json` and in `themes/theme.schema.json`.

## Color tokens: `inputBorder` and `focusRing`

- `inputBorder` is the outline of text fields, the composer and search fields. It must have at least **3:1** contrast against `surface` (WCAG non-text contrast). The `border` outline stays for compartments.
- `focusRing` must also have at least **3:1** contrast against `surface`. The test in `apps/pi_frame/test/design_tokens_test.dart` checks both `inputBorder` and `focusRing` on the official `piframe-dark` and `piframe-light` themes. That test does not check user themes.
- The official themes declare `inputBorder` explicitly (`#627699` on dark, `#7d8aa0` on light).
- A theme that does not declare `inputBorder` derives it: it starts from `borderStrong` and moves toward `textPrimary` until it reaches 3:1 on `surface`.

## Spacing, size, typography and motion tokens

These values do not depend on the theme. They are Dart constants in the `pi_frame_theme` package.

| Token | Values | Access |
|---|---|---|
| Spacing | `x1`=4, `x2`=8, `x3`=12, `x4`=16, `x6`=24, `x8`=32, `x12`=48 (page gutter on wide layouts) | `FrameSpace.x4` |
| Sizes | `rowList`=28, `rowForm`=40, `hitMin`=28, `iconSm`=14, `icon`=16, `iconLg`=20, `paneHeader`=40. `iconSm` is only for chips and dense bars; everything else uses `icon` | `FrameSize.rowList` |
| Typography | `caption` 11/16, `label` 12/16 (w500), `body` 13/20, `bodyLarge` 14/20, `title` 16/22 (w600), `heading` 20/26 (w600), `display` 28/32 (w600), `mono` 12/18, `monoBody` 13/20 | `FrameText.of(context).label` |
| Radii | `radiusSm`=6, `radiusMd`=10, `radiusLg`=14, `radiusPill`=999 | `FrameTokens.radiusSm` (per theme) |
| Motion | `instant`=0, `micro`=120, `smallExit`=120, `small`=160, `panel`=240, `panelExit`=180, `dialog`=180, `dialogExit`=120, `firstRun`=300, `stagger`=100, `crossFade`=120, `debounce`=300, `tooltipWait`=300, `pulseLoop`=1400, `shimmerLoop`=3600, `launchReveal`=620 ms (`pulseLoop` and `shimmerLoop` stop with *Reduce motion*); curves `enterCurve`=`Cubic(0.23, 1, 0.32, 1)`, `panelCurve`=`Cubic(0.32, 0.72, 0, 1)` | `FrameMotion.panel` (app) or `FrameMotionTokens.panel` (theme) |

The app adds a few motion constants of its own in `apps/pi_frame/lib/ui/motion.dart`: `textShimmerLoop`=2000 ms (the shimmer on a working step group header), `stepFadeIn`=240 ms, `stepFadeOut`=180 ms and `stepFadeCurve`=`Curves.easeInOut`.

- **Typography:** UI roles use `uiFontFamily` (Schibsted Grotesk) and the `mono` roles use `monoFontFamily` (Source Code Pro). Barlow Condensed (`headingFontFamily`) is reserved for the brand and pane headers and does not appear in these roles. The minimum size is 11 px. `FrameText` is registered as a `ThemeExtension` in every `ThemeData` built from the theme.
- **Motion:** `FrameMotionTokens` is the single source. `FrameTokens.pressDuration`, `panelDuration`, `enterCurve` and `panelCurve` read the same constants as `FrameMotion`, so they cannot drift apart.

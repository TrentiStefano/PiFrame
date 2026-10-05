---
name: Pi-Crust — Precision
description: "A sharply composed workspace for focused Pi sessions."
colors:
  light-background: "#F8F9F5"
  light-chassis: "#D3D8D2"
  light-surface: "#F8F9F5"
  light-raised: "#E6E9DE"
  light-display: "#191D1A"
  light-ink: "#191D1A"
  light-secondary-ink: "#5B4A3B"
  light-muted-ink: "#586253"
  light-green: "#0D703F"
  light-green-on: "#F3F4EC"
  light-yellow: "#F1B73A"
  light-red: "#E6423A"
  light-border: "#C3CABC"
  light-strong-border: "#818A7D"
  light-success: "#0D703F"
  light-warning: "#805500"
  light-danger: "#B42D26"
  light-information: "#3C606A"
  light-user-field: "#E6E9DE"
  light-thinking: "#5B4A3B"
  light-added: "#DDEBDD"
  light-added-ink: "#0D703F"
  light-removed: "#F3DDD5"
  light-removed-ink: "#9C2A24"
  dark-background: "#151916"
  dark-chassis: "#262D27"
  dark-surface: "#202621"
  dark-raised: "#303931"
  dark-display: "#080C09"
  dark-ink: "#F0F2E9"
  dark-secondary-ink: "#CAD0C5"
  dark-muted-ink: "#A7B2A3"
  dark-green: "#83CCA1"
  dark-green-on: "#173024"
  dark-yellow: "#F1B73A"
  dark-red: "#E6423A"
  dark-border: "#424D43"
  dark-strong-border: "#657568"
typography:
  display:
    fontFamily: "BarlowCondensed"
    fontSize: "56px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.5px"
  brand:
    fontFamily: "BarlowCondensed"
    fontSize: "38px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.4px"
  body:
    fontFamily: "SchibstedGrotesk"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  code:
    fontFamily: "SourceCodePro"
    fontSize: "12.5px"
    fontWeight: 400
    lineHeight: 1.5
rounded:
  sm: "2px"
  md: "2px"
  lg: "4px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  2xl: "32px"
  3xl: "48px"
components:
  action-primary:
    backgroundColor: "{colors.light-green}"
    textColor: "{colors.light-green-on}"
    rounded: "{rounded.sm}"
  display-strip:
    backgroundColor: "{colors.light-display}"
    textColor: "{colors.light-background}"
    rounded: "{rounded.sm}"
---

# Design System: Pi-Crust — Precision

## Overview

**Creative North Star: Precision**

Pi-Crust is a working instrument for Pi sessions, not a miniature stereo or a chat template. Industrial clarity governs the interface: a pale mineral chassis, emphatic typographic marks, a near-black information face, and controls whose purpose is obvious. Rams' honesty and restraint meet Teenage Engineering's unapologetic scale and graphic confidence. Product references inform proportion and hierarchy; Pi-Crust keeps its own name, glyph, and controls.

The user's DR10 palette remains source of identity. Green identifies Pi-Crust and primary action; yellow and red communicate real states. Heavy Barlow Condensed display lettering contrasts with measured Schibsted Grotesk reading text. The dark display strip organizes active session identity and composition. Broad open transcript area balances the precise session rail and tool readouts.

**Key characteristics:** mineral enclosure; sharp dark display fields; bold condensed identity; precise type hierarchy; signal color used for function; brief, interruptible motion.

## Colors

Light remains default. The light background uses `#F8F9F5`, a contrast-safe near-white derived from the user's DR10 neutrals; `#D3D8D2` defines chassis surfaces. `#191D1A` carries display hierarchy. Deep green `#0D703F` anchors identity, selection-independent primary actions, and settled/working states. Yellow `#F1B73A` and red `#E6423A` stay reserved for warning and danger emphasis. Dark mode maps these roles onto a near-black green chassis. `assets/themes/crust-light.json` and `crust-dark.json` remain normative for complete colors, syntax, and semantic aliases.

**The Signal Rule.** Yellow and red indicate a genuine state or interruption. Never use them as decorative highlights.

**The Chassis Rule.** Keep green associated with Pi-Crust; use near-black fields to organize important information, not as global decoration.

## Typography

**Display and identity:** Barlow Condensed, bundled locally. **Interface:** Schibsted Grotesk, bundled locally. **Code:** Source Code Pro, bundled locally.

The compressed display face gives Pi-Crust its industrial voice. Interface copy remains open and readable; monospace appears only for code, paths, or measured values.

### Hierarchy
- **Display** (700, 56px, 1.0): empty-state title and key product statements; scale down to 68px on narrow layouts when space permits.
- **Brand** (700, 38px): Pi-Crust wordmark in native and web application header; compact header uses 30px.
- **Section title** (600, 24–32px): workspace, settings, and session identity.
- **Body** (400, 14–15px, 1.5–1.6): transcript, description, and operating copy.
- **Code** (400, 12.5px, 1.5): code block content in Source Code Pro.

## Layout

The application header is 76px high. The 280px session index sits beside an expandable conversation surface; the 320px inspector docks at widths of 1280px and above, then moves into an explicit end drawer. Below 900px, session navigation uses a drawer. Session identity occupies its own near-black strip; transcript content stays open rather than nesting every turn inside a card. The composer anchors the lower edge as a near-black command field.

Transcript measure remains capped at 820px; settings use a 960px content measure. Spacing follows a 4px unit and the observed 4, 8, 12, 16, 24, 32, 48px scale. Windows caption height shares the 76px app header; its native drag area and minimize/maximize/close controls remain operable. Minimum native window size is 680×480.

## Elevation & Depth

The interface relies on contrast between chassis, open work field, and near-black display surfaces, plus 1px rules. Most work surfaces stay flat. Modal and command surfaces use the existing Flutter Material elevation; do not add ambient card shadows to ordinary session or transcript content. The theme JSON's elevation values document the token set; components should use measured platform elevation rather than treating those tokens as permission for decoration.

**The Plane Rule.** Distinguish hierarchy with surface value and alignment before adding shadow.

## Shapes

Geometry is square and controlled: 2px small/medium corners and 4px large corners. One-pixel rules describe panel boundaries; display surfaces use straight edges. No pill-shaped cards or ornamental hardware contours. Keep resize handles and native Windows affordances functional.

## Components

- **Application header:** mineral chassis, 1px lower rule, original four-part P mark, condensed wordmark, compact actions, and integrated Windows caption controls. Drag only noninteractive header space.
- **Session index:** flat mineral rail, prominent condensed heading, thin rules, compact search and filters. Selected session is a near-black plate with high-contrast content; status marks retain semantic meaning.
- **Session display:** near-black strip for title/path/state, open transcript beneath. User messages use the DR10 neutral field and a fine bottom rule; assistant prose sits directly on the work plane. Tools, reasoning, code, and diffs retain their distinct inspectable states.
- **Composer:** near-black anchored surface with a thin bright outline around the editable region. Send, steer, follow-up, and interrupt remain separate actions; queued text and errors stay visible.
- **Workspace inspector:** explicit dock or drawer with its own heading strip, live model/reasoning choices, Git status, and safe session actions.
- **Windows caption:** custom drag region and three accessible native window actions, with hover/pressed feedback and maximize state.
- **Primary action:** DR10 green fill, high-contrast text, 2px corner; pointer down compresses subtly while keyboard invocation stays instant.

## Do's and Don'ts

### Do:
- **Do** keep `#0D703F`, `#F1B73A`, and `#E6423A` tied to identity and meaningful state.
- **Do** use bundled Barlow Condensed for Pi-Crust's authored display/brand voice and Schibsted Grotesk for reading.
- **Do** preserve the open transcript, session display strip, and dark composer surfaces.
- **Do** keep Windows caption controls, drag, resize, maximize, minimize, close, DPI, and reduced motion functional.
- **Do** keep startup reveal brief, once per launch, interruptible, and visibly secondary to already-available work.

### Don't:
- **Don't** copy Braun or Teenage Engineering logos, product controls, or proprietary assets.
- **Don't** add fake dials, fake metrics, ornamental device frames, glass, gradients, or generic nested cards.
- **Don't** animate keyboard commands or replay entrances on session changes.
- **Don't** apply warning or danger color when no warning or danger exists.

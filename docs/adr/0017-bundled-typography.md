# ADR 0017: Bundled Fonts

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #8
- **Amended:** 2026-11-23 (the fonts actually bundled; see the amendment below)


## Context

Visual typography must be identical and high-quality across Windows, macOS, and Web regardless of installed system fonts.

## Decision

Bundle open-source fonts (SIL OFL) for UI and code within the app assets. The original decision named Inter (UI) and JetBrains Mono (code); the app ships other fonts, see the amendment.

## Amendment (2026-11-23)

The fonts bundled in `apps/pi_frame/assets/fonts/` and declared in `apps/pi_frame/pubspec.yaml`, with the roles [DESIGN.md](../../DESIGN.md#typography) gives them, are:

- **Schibsted Grotesk** (`SchibstedGrotesk`): all UI text.
- **Barlow Condensed** (`BarlowCondensed`, SemiBold and Bold): the brand and pane headings only.
- **Source Code Pro** (`SourceCodePro`): code, diffs, paths and other mono text.

All three are under the SIL Open Font License; the license files sit next to the fonts. Inter and JetBrains Mono are not bundled. The rest of the decision (bundled fonts, not system fonts) stands.

## Consequences

Consistent modern aesthetic across all platforms. JSON themes can override font families with graceful fallback.

## Alternatives Rejected

System fonts (inconsistent rendering across platforms).

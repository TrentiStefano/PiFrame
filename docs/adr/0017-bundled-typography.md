# ADR 0017: Bundled Fonts: Inter (UI) + JetBrains Mono (Code)

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #8


## Context

Visual typography must be identical and high-quality across Windows, macOS, and Web regardless of installed system fonts.

## Decision

Bundle open-source Inter (SIL OFL) for UI and JetBrains Mono (SIL OFL) for code within the app assets.

## Consequences

Consistent modern aesthetic across all platforms. JSON themes can override font families with graceful fallback.

## Alternatives Rejected

System fonts (inconsistent rendering across platforms).

# ADR 0014: Distribution: Daemon as Sidecar Binary (Node SEA) Inside App Bundle

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #3


## Context

Users installing Pi-Crust must not be forced to manually install or manage Node.js.

## Decision

Bundle daemon with esbuild and package as single-file Node Single Executable Application (SEA) bundled inside the Flutter app.

## Consequences

Self-contained distribution. Pi remains independent. Uninstalling Pi-Crust removes app and daemon without touching ~/.pi/.

## Alternatives Rejected

Requiring user to pre-install Node 22 (poor desktop app onboarding experience).

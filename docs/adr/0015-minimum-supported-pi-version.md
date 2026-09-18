# ADR 0015: Minimum Supported Pi Version: v0.85.0

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #5


## Context

Pi-Crust requires the modern Pi RPC interface, including session trees, assistantMessageEvent framing, and extension UI capabilities.

## Decision

Enforce v0.85.0 as the minimum supported Pi version, verified via semver probe on startup.

## Consequences

Daemon enters degraded state with actionable upgrade instructions if Pi < v0.85.0 or missing.

## Alternatives Rejected

Supporting legacy Pi versions (requires fragile polyfills and breaks protocol consistency).

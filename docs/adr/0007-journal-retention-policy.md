# ADR 0007: Journal Retention: max(2,000 events, 8 MB) with Snapshot Every 500 Events

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #2


## Context

Memory and disk space must be bounded while providing seamless reconnection for long-running sessions.

## Decision

Retain up to 2,000 events or 8 MB per session, snapshot every 500 events, and preserve spill files for 24 hours.

## Consequences

Exceeding the window smoothly degrades to sending a full authoritative snapshot, which is always correct.

## Alternatives Rejected

Unbounded retention (uncontrolled memory/disk growth); Very small window (frequent full-snapshot resyncs).

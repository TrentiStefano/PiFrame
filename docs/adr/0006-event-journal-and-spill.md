# ADR 0006: Journal: Ring Buffer in Memory + Disk Spill per Session

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

Replay must survive GUI disconnects and transient daemon restarts without turning into a secondary authoritative transcript database.

## Decision

Implement an in-memory ring buffer with append-only disk spill under ~/.pi-crust/journal/<sessionId>/ and periodic snapshots.

## Consequences

Zero data loss during UI disconnects. Bounded resource usage with guaranteed monotonic sequence numbering.

## Alternatives Rejected

SQLite (heavyweight for bounded append-only stream); Memory-only (loses replay on daemon restart).

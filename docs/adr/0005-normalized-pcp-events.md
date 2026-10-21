# ADR 0005: Daemon Exposes Normalized Events, Not Raw Pi JSONL

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

Directly forwarding Pi JSONL couples Flutter UI to internal changes of Pi, violating isolation requirements.

## Decision

The daemon normalizes all Pi events into stable PiFrame Protocol (PCP/1) events via PiEventAdapter.

## Consequences

Insulates UI from Pi upstream changes. An optional debug capability (debug.raw-pi-events) allows inspection when needed. Adapter covered by golden test fixtures.

## Alternatives Rejected

Pure passthrough (tightly couples Flutter to specific Pi versions).

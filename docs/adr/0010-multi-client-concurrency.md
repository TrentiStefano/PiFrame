# ADR 0010: Multi-Client: Broadcast Events, Exclusive Claim for UI Requests

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #9


## Context

Multiple GUI windows or browser tabs may attach to the same session, but interactive dialogs (confirm, select, input, editor) require a single decision maker.

## Decision

Broadcast all session events to all attached clients. Enforce exclusive 30s renewable claim lease for interactive extension UI dialogs.

## Consequences

First client to claim responds; other clients observe read-only indicator. Zero duplicate responses.

## Alternatives Rejected

Single-client restriction (blocks desktop + web coexistence); Free-for-all responses (race conditions).

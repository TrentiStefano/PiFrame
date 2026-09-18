# ADR 0009: Worker Idle Timeout: 30 Minutes Default, User Configurable

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #4


## Context

Multiple idle Pi processes consume memory, but work in progress must never be interrupted.

## Decision

Default 30-minute idle worker shutdown (0 = never), configurable via daemon.setConfig and GUI Settings. Workers in active/working/awaiting_user states are never killed.

## Consequences

Prevents phantom processes while safeguarding active generation. Immediate timer updates across all connected GUIs via daemon.configChanged.

## Alternatives Rejected

No idle timeout (process leaks); Aggressive timeout (kills inactive sessions too quickly).

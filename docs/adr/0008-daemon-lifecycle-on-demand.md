# ADR 0008: Daemon Lifecycle: On-Demand Detached Process with Single-Instance Lock

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #1


## Context

Users do not want an intrusive permanent OS background service installed without explicit necessity.

## Decision

The daemon is not a permanent OS service. It is spawned on-demand detached by the GUI if the GET /api/health probe fails.

## Consequences

Safe, unobtrusive lifecycle with lockfile PID verification. The agent continues working in background when GUI is closed.

## Alternatives Rejected

Always-running system service (invasive, requires root/admin privilege and difficult uninstall).

# ADR 0001: Daemon Runtime: Node.js 22 LTS

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

Pi-coding-agent is implemented in TypeScript/Node.js. The daemon must manage subprocesses, JSONL stdio framing, WebSockets, filesystem watchers, and Git inspection.

## Decision

Use Node.js 22+ LTS for pi-agentd.

## Consequences

Enables direct compatibility with Node ecosystem (ws, chokidar), mature subprocess/stdio APIs, and single-file executable packaging via Node SEA. Slightly slower startup than Bun, but completely stable.

## Alternatives Rejected

Bun (less predictable subprocess stdio edge cases and rapid breaking change cadence); Rust (overkill for MVP, losing direct TS type alignment with Pi).

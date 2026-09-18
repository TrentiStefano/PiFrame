# ADR 0004: Flutter State Management: Riverpod 2 (code-gen off)

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

The Flutter GUI manages multi-session streams, live agent delta updates, connection state machines, and local UI preferences across 3 layout columns.

## Decision

Use Flutter Riverpod 2 without code generation.

## Consequences

Clean separation between presentation state, live runtime state, and authoritative Pi session state. Supports scoped session providers and easy headless testing.

## Alternatives Rejected

BLoC (excessively verbose for high-frequency text delta streams); signals/setState (insufficient multi-session fanout and lifecycle scoping).

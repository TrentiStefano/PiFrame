# ADR 0003: Protocol Source of Truth: JSON Schema in packages/pcp-spec

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

Both TypeScript (daemon) and Dart (Flutter) must maintain synchronized types and wire validation without silent drift.

## Decision

Define normative protocol schemas in packages/pcp-spec/*.schema.json with automated codegen to TS and Dart.

## Consequences

Single source of truth. Shared test fixtures validate both implementations identically. Codegen-drift CI check ensures zero divergence.

## Alternatives Rejected

Hand-written types on both sides (guaranteed eventual drift); Protobuf/CBOR (premature binary optimization making debugging harder).

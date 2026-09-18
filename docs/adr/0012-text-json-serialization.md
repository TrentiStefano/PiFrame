# ADR 0012: Serialization: Textual JSON in PCP/1

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

Protocol messages must be easy to debug, inspect, and consume across Node and Flutter Web/Desktop.

## Decision

PCP/1 uses strict JSON text frames. The encoding field in handshake allows future CBOR/MessagePack extensions if needed.

## Consequences

Standard JSON debugging, native browser support, simple tooling, zero binary compilation friction in MVP.

## Alternatives Rejected

Protobuf / MessagePack upfront (premature optimization for loopback IPC).

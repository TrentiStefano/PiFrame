# ADR 0011: Authentication: 256-Bit Token in ~/.piframe/runtime/daemon.token + Web Bootstrap Cookie

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #6


## Context

The daemon executes agent commands on loopback. Web browsers cannot set custom headers during WebSocket handshake and query strings leak into logs.

## Decision

Generate a random 256-bit token on daemon startup in daemon.token (chmod 600). Transmit in PCP hello frame. Web client uses HttpOnly SameSite=Strict cookie via GET /api/session-bootstrap.

## Consequences

Robust loopback security. No token leakage in URLs or logs. Seamless zero-configuration browser access on localhost.

## Alternatives Rejected

Token in query string (log/referrer leakage); No authentication (arbitrary code execution risk).

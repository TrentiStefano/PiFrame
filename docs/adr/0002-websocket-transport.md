# ADR 0002: WebSocket Transport: ws + node:http

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

The daemon needs a robust loopback communication channel for Flutter Desktop and Web clients, while serving static Flutter Web assets.

## Decision

Use ws library integrated with standard node:http.

## Consequences

Full control over connection handshake, Origin headers, upgrade requests, custom close codes, and backpressure. Same HTTP server serves Flutter Web assets.

## Alternatives Rejected

socket.io (proprietary protocol framing, unofficial Dart client); uWebSockets.js (native build dependencies with negligible loopback performance benefit).

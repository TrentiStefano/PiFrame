# ADR 0013: Local Web Hosting: Served by Daemon with Separated Path Namespace

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18


## Context

Users should be able to open http://127.0.0.1:<port>/ in their browser without running a separate web server.

## Decision

The daemon HTTP server serves static Flutter Web assets on GET /, API endpoints on /api/*, and WebSocket on /api/ws.

## Consequences

Zero-setup web experience. Clean URL namespace allows future remote deployment of static assets.

## Alternatives Rejected

Separate static web server process (unnecessary operational overhead).

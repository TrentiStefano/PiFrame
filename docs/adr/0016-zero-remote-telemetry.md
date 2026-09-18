# ADR 0016: Telemetry: Zero Remote Data Collection (Local Only, No Opt-in)

- **Status:** Accepted
- **Confirmation Date:** 2026-09-18
- **Stakeholder Decision Reference:** Implementation Plan §10, Item #7


## Context

User privacy and data sovereignty are top priorities. No telemetry, usage statistics, or crash reports should ever leave the user machine.

## Decision

Zero remote telemetry in any form, not even opt-in. Logging is purely local with manual exportable diagnostic bundles.

## Consequences

Complete privacy. No third-party tracking libraries or analytics dependencies permitted in codebase.

## Alternatives Rejected

Opt-in telemetry (creates privacy attack surface and maintenance burden; rejected by stakeholder).

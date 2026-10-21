# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Pi coding-agent users who want a desktop or web GUI to manage sessions and interact with Pi coding agent. They use a terminal-based coding harness and want the comforts of a GUI application.

## Product Purpose

PiFrame's Flutter client provides a graphical interface for managing Pi coding-agent sessions and interacting with the agent. Success means users can work with Pi through a GUI while Pi remains the source of truth for session history.

## Positioning

PiFrame adds a desktop and web GUI to Pi coding agent, which is otherwise a terminal coding harness. The Flutter client works with a persistent local daemon so users can reconnect to ongoing work without taking ownership of Pi's session history.

## Operating Context

Users run PiFrame on Windows, macOS, or Web alongside the PiFrame daemon. They select and manage sessions, send messages, follow streamed responses and tool activity, inspect code and diffs, and respond to Pi extension dialogs. The daemon runs locally and is reached over loopback.

## Capabilities and Constraints

- Targets Windows, macOS, and Web. iOS and Android are out of scope.
- Provides session navigation, a streaming transcript, reasoning and tool activity views, code and diff inspection, a composer, command palette, settings, and Pi extension dialogs.
- Works with the PiFrame daemon for agent communication and reconnection. The client owns presentation, session projection, and command dispatch; it does not own agent processes or session files.
- Pi remains the sole owner and source of truth for session history in `~/.pi/agent/sessions/`.
- The daemon is bound to `127.0.0.1`; connections use bearer-token authentication and strict origin checks.
- No remote telemetry, analytics SDKs, external tracking, or outbound network requests outside loopback.

## Brand Commitments

The product name and original mark are PiFrame. The visual direction is Bento spatial grouping with official Catppuccin Latte/Frappé colors and modest rounded, subtly bordered surfaces throughout the application. Root `DESIGN.md` is authoritative; prior external design-language references are retired.

## Evidence on Hand

The repository contains the Flutter client, bundled dark and light themes, and automated widget and domain tests under `apps/pi_frame/`. The root `README.md` documents the product architecture, features, privacy constraints, and build and test commands. Do not invent testimonials, customer names, adoption figures, or external endorsements.

## Product Principles

- Preserve Pi's ownership of session history.
- Keep agent work available across GUI disconnects and reconnects.
- Keep communication local and avoid remote telemetry.
- Give Pi coding-agent users GUI-based session management and interaction.

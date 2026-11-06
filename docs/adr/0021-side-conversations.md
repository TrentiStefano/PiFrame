# ADR 0021: Ephemeral Read-Only Side Conversations

- **Status:** Accepted
- **Confirmation Date:** 2026-11-10

## Context

Users working on complex tasks in PiFrame frequently need to ask clarifying or auxiliary questions (such as "Explain how this function works", "What were the edge cases discussed earlier?", or "Review this diff without changing files") without polluting the primary conversation transcript, without triggering unintended modifications, and without risking main session state divergence.

### Architectural Options Evaluated

1. **Option A: `rpiv-btw` / Extension UI Hook**
   - Pi extensions can register slash commands or dialog hooks (e.g. `/btw`).
   - *Limitation:* Extension UI hooks in Pi RPC require `ctx.hasUI === true` and interactive TUI dialog handling. Furthermore, extensions executed in this mode have zero built-in tool execution capabilities (`tools: []`), preventing the assistant from inspecting workspace files or cross-referencing code.

2. **Option B: `pi-btw` TUI Sub-Session / Session Fork**
   - Spawning a sub-session using Pi's `--fork <sessionFile>` or duplicating the session file on disk.
   - *Limitation:* Forking writes a new `.jsonl` session file into Pi's authoritative storage (`~/.pi/agent/sessions/`). If written by the daemon, it violates PiFrame's hard invariant that the daemon must never write to Pi session files. Furthermore, persistent fork files clutter the session index and introduce disk cleanup overhead.

3. **Option C (Chosen): Daemon-Managed Ephemeral `--no-session` Read-Only Worker**
   - The daemon manages dedicated, ephemeral Pi RPC worker processes spawned with `--mode rpc`, `--no-session`, `--tools read,grep,find,ls`, `--no-mcp`, `--no-extensions`, `--no-skills`, `--append-system-prompt <contextFile>`.
   - The snapshot of the main conversation is rendered to a temporary markdown file passed via `--append-system-prompt`, accompanied by a strict read-only guardrail preamble.
   - Events are published on a dedicated stream (`streamId = side_<ulid>`) and kept only in an in-memory ring buffer (never spilled to disk or appended to the main session journal).

## Decision

Implement Option C in `apps/agentd/src/side/SideConversationManager.ts` with the following architectural choices:

1. **Snapshot via System Prompt File instead of Session Copy:**
   - **No Disk Spilling / No Session Mutation:** Reading conversation messages via `get_messages` (if worker is alive) or daemon transcript entries, and rendering to `~/.piframe/runtime/side/<sideId>/context.md` (directory mode `0700`, file mode `0600`).
   - **Strict Character Cap:** Capped at ~120,000 characters (preserving the most recent turns and prepending an explicit truncation notice if capped).
   - **Decoupled from Pi Storage:** Completely avoids creating or modifying Pi session files in `~/.pi/agent/sessions/`.
   - **Guaranteed Cleanup:** The temporary directory `~/.piframe/runtime/side/<sideId>/` is deleted immediately upon closing the side conversation or daemon shutdown.

2. **Strict Tool Restriction & Isolation Guarantees:**
   - **CLI Flags:** Worker process is spawned with `--tools read,grep,find,ls`, `--no-mcp`, `--no-extensions`, `--no-skills`. Mutating tools (`bash`, `edit`, `write`) are never declared.
   - **Runtime Tool Verification:** On startup, `get_state` is queried. If active tools are exposed, the daemon verifies that every tool is an exact subset of `{read, grep, find, ls}`; if any unsafe tool is found, the worker is immediately terminated with `SIDE_UNSAFE_TOOLS`.
   - **RPC Allowlist in Transport Wrapper:** The worker transport wrapper (`SideTransport`) strictly blocks any RPC command other than `prompt`, `abort`, and `get_state` (throwing `SIDE_RPC_BLOCKED`).
   - **Byte-Identical Main Session Isolation:** The primary session file remains 100% byte-identical before and after side conversation activity.
   - **Journal Isolation:** Main session journals receive zero side events. All side events exist exclusively in a bounded in-memory buffer per side thread.

3. **Protocol & Stream Governance:**
   - Commands: `side.open` `{sessionId, question?}`, `side.prompt` `{sideId, text}`, `side.abort` `{sideId}`, `side.close` `{sideId}`.
   - Stream ID: `side_<ulid>`.
   - Events: `side.opened` `{sideId, parentSessionId, model}`, `side.closed` `{sideId, reason: 'user'|'idle'|'parentClosed'|'error'|'shutdown'}`, along with standard normalized events (`text.delta`, `message.completed`, `run.settled`, etc.).
   - Stream Read-Only Guard: Any non-attach command targeting a side `streamId` is rejected with `SIDE_STREAM_READ_ONLY`.
   - Concurrency & Lifecycle Bounds: Max 1 side thread per parent session (subsequent opens return the existing thread), max 4 side threads total, 10-minute idle worker shutdown, automatic termination when parent session closes, and complete cleanup on daemon shutdown.
   - Remote Permissions: In remote `view` mode, `side.abort` and `side.close` are permitted (safety controls), while `side.open` and `side.prompt` require `control` mode (`REMOTE_FORBIDDEN` in view mode).

## Residual Risks & Mitigations

1. **Extension-Registered Tools Risk:**
   - *Risk:* If a future or customized version of Pi allows extension-registered tools to bypass `--tools <list>`, unauthorized tools might become declared.
   - *Mitigation:* We pass `--no-extensions` (and `--no-skills`, `--no-mcp`), and additionally verify the active tools returned by `get_state` on worker startup against the allowed whitelist `{read, grep, find, ls}`, aborting with `SIDE_UNSAFE_TOOLS` if any unauthorized tool is detected.
2. **Memory Footprint of Concurrent Workers:**
   - *Risk:* Multiple Node.js / Pi worker processes consume host RAM.
   - *Mitigation:* Hard limit of max 4 concurrent side threads host-wide, max 1 per parent session, and 10-minute idle termination.

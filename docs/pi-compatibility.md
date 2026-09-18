# Pi RPC Compatibility Verification Report

- **Date:** 2026-09-18
- **Target Pi Version Detected:** `v0.85.1`
- **Minimum Supported Pi Version:** `v0.85.0` (D15)
- **Node.js Environment:** `v25.9.0` (x64)
- **Host OS:** Windows 11 (win32 x64)
- **Verification Status:** **CONFIRMED & COMPATIBLE** (All invariants verified against `@earendil-works/pi-coding-agent@0.85.1`)

---

## 1. Environment & Package Metadata

| Property | Value |
|---|---|
| Package | `@earendil-works/pi-coding-agent` |
| Version | `0.85.1` |
| Core Library | `@earendil-works/pi-agent-core` |
| RPC Entry | `dist/modes/rpc/rpc-mode.js` & `dist/bundle/cli.js` |
| TypeScript Types | `dist/modes/rpc/rpc-types.d.ts`, `dist/modes/json-event.d.ts`, `dist/core/agent-session.d.ts` |

---

## 2. RPC Protocol Verification Table

| Invariant / Feature | Plan Specification | Observed in `v0.85.1` | Status | Notes |
|---|---|---|---|---|
| **Framing** | Strict LF-delimited JSON lines; no `readline` (supports U+2028/U+2029) | `dist/modes/rpc/jsonl.js` explicitly states: *"Framing is LF-only... This intentionally does not use Node readline."* | **Confirmed** | Strip trailing `\r` on Windows CRLF. |
| **Command Correlation** | Optional `id` ULID/UUID on commands, reflected in `response` | `RpcCommand` has `id?: string`, and `RpcResponse` returns `id?: string`. | **Confirmed** | Responses match `command` and `id`. |
| **Message Streaming** | `message_update` does **NOT** contain cumulative assistant text; client builds via `contentIndex`; `message_end.message` is authoritative | `dist/modes/json-event.d.ts`: `toJsonEvent` strips cumulative snapshot, only emits incremental `assistantMessageEvent`. | **Confirmed** | Critical UI invariant: accumulate by `contentIndex`, swap on `message_end`. |
| **Tool Execution Progress** | `tool_execution_update.partialResult` is **cumulative** (replace, do not concatenate) | Confirmed in core `AgentEvent` and RPC output definitions. | **Confirmed** | Reducer must replace partial result buffer on each update. |
| **Agent Completion Semantics** | `run.ended` (`agent_end`) does not mean finished; only `run.settled` (`agent_settled`) terminates | `AgentSessionEvent` defines both `agent_end` (with `willRetry: boolean`) and `agent_settled`. | **Confirmed** | UI must wait for `agent_settled` before presenting final idle state. |
| **Streaming Prompt Rule** | `prompt` during active streaming requires `streamingBehavior` (`"steer"` \| `"followUp"`) | In `rpc-types.d.ts`, `prompt` command specifies `streamingBehavior?: "steer" \| "followUp"`. | **Confirmed** | Dispatcher rejects prompt without streamingBehavior if streaming. |
| **Clear Queue Recovery** | `clear_queue` returns removed `steering` and `followUp` message arrays | In `rpc-types.d.ts`, `response` to `clear_queue` has `data: { steering: string[], followUp: string[] }`. | **Confirmed** | Powers the `Esc` interrupt semantics (restoring text in composer). |
| **Extension UI Dialogs** | Only `select`, `confirm`, `input`, `editor` require `extension_ui_response` | In `rpc-types.d.ts`, only these 4 methods have return values; others (`notify`, `setStatus`, `setWidget`, `setTitle`, `set_editor_text`) are fire-and-forget. | **Confirmed** | Client must never send response for fire-and-forget methods. |
| **Extension UI Timeout** | Handled upstream by Pi runtime | `RpcExtensionUIRequest` specifies optional `timeout?: number`. Upstream auto-cancels on expiry. | **Confirmed** | Client closes modal upon receiving resolution. |
| **Session Tree & Navigation** | `get_entries`, `get_tree`, `fork`, `clone`, `switch_session` | All commands and signatures exist with matching payloads. `get_entries` supports `since?: string` durable cursor. | **Confirmed** | Tree nodes use `id`, `parentId`, and `children`. |
| **Slash Commands** | `get_commands` lists commands with `source: "extension" \| "prompt" \| "skill"` | `RpcSlashCommand` in `rpc-types.d.ts` matches specification exactly. | **Confirmed** | Extension commands must be dispatched as `prompt`. |
| **Session Persistence Path** | `~/.pi/agent/sessions/--<path>--/<timestamp>_<uuid>.jsonl` | Read-only index scans directory; GUI never modifies or deletes anything in `~/.pi/`. | **Confirmed** | Tree v3 session format verified against `docs/session-format.md`. |

---

## 3. Deviations & Observations

No breaking deviations were detected between `v0.85.0` (baseline specified in plan) and `v0.85.1` (installed version).

### Windows Specific Note
- On Windows, `pi.cmd` passes arguments through `cmd.exe`. Direct invocation of `dist/bundle/cli.js` via Node child_process avoids `cmd.exe` quoting and deprecation warnings while ensuring true unbuffered pipe behavior.
- The `DaemonLocator` and `StdioPiTransport` will resolve the Node executable and CLI entry script cleanly across Windows, macOS, and Linux.

---

## 4. Archived Reference Artifacts

The following upstream files have been archived under `tools/recon/reference/` for reference:
- `rpc.md`
- `sessions.md`
- `session-format.md`
- `rpc-types.d.ts`
- `rpc-client.d.ts`
- `jsonl.d.ts` & `jsonl.js`
- `json-event.d.ts`
- `agent-session.d.ts`
- `agent-core-types.d.ts`

Golden test fixtures (14 scenarios) have been generated in `packages/pcp-spec/fixtures/pi/*.jsonl`.
Automated drift detection test is located at `tools/recon/verify.ts`.

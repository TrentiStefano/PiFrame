---
name: piframe-ui-harness
description: Drive and verify PiFrame's real Flutter UI with its isolated desktop harness. Use when changing or verifying PiFrame UI, testing a UI change, driving the app, or capturing PiFrame UI screenshots.
---

# PiFrame UI harness

Use this skill for real Flutter UI work in the PiFrame monorepo.

## Why

The user may be using their own PiFrame at the same time. The harness runs an isolated, off-screen instance with fake-pi. It never touches the user's window, mouse, or daemon.

## Loop

Run commands from the repository root. Start or reuse the isolated run:

```sh
pnpm harness start [--scenario <name>] [--seed] [--size <WxH>]
pnpm harness seed
pnpm harness scenarios
pnpm harness scenario <name>
```

Discover the current UI before acting:

```sh
pnpm harness tree
```

Use selectors from the tree: `key:<key>` or `text:<text>`; append `#N` to target a matching index, e.g. `text:New session#2`. Tree entries include covered widgets and button tooltips/labels; `truncated` reports a reached cap. Prefer stable `ValueKey<String>` keys. Add one to any control that lacks a stable key.

Drive the app with `pnpm harness tap <selector>`, `tapAt <x> <y>`, `rightClick <selector>`, `doubleTap <selector>`, `longPress <selector>`, `drag <selector> <dx> <dy>`, `type <text> [--into <selector>]`, `key <name>`, `hover <selector>`, `scroll <selector> <dy>`, and `resize <WxH>`. Inspect bounded widget trees with `tree [--filter text] [--limit N] [--depth N]`. Set harness-only media with `media [--text-scale 1.5] [--reduce-motion on|off] [--brightness light|dark]` or restore defaults with `media --reset`. Capture and inspect a real screenshot:

```sh
pnpm harness shot <descriptive-label>
```

Read the generated PNG. Critique the actual UI, then edit `apps/pi_frame/lib/` and repeat. After edits, choose the smallest correct refresh:

- `pnpm harness reload` for Dart UI changes.
- `pnpm harness restart` for state or initialization changes.
- `pnpm harness rebuild` for native, `pubspec`, or `main` changes.
- `pnpm harness rebuild --daemon` for `apps/agentd` changes.

Run `pnpm harness stop` when done. Always stop the run, including after screenshot review.

## Seed fixtures and switching scenarios

`pnpm harness start --seed` or `pnpm harness seed` creates isolated fixtures below the run home: a dirty Git workspace with staged/unstaged/untracked changes and `feature/demo`, a second repo, five session JSONL files (one 150-message history and one linked `worker#…` child), a pinned session, and two MCP server configs. It is repeatable and reports when Git is unavailable. It never writes outside the safety-checked harness home.

Use `pnpm harness scenarios` to discover available names. `start --scenario <name>` sets the initial scenario; `pnpm harness scenario <name>` validates and switches the control file without restart. fake-pi checks that file for every prompt, so the new scenario applies on the next prompt.

Example feature → route recipes:

- Git Changes / diff staging: `start --seed`, open the seeded workspace, find `notes.md` with `tree --filter notes.md`.
- Sessions, pins, session paging, worker children: `start --seed`, open Sessions, choose `Long history paging` or `Workspace planning`.
- MCP settings: `start --seed`, Settings → Pi CLI → Manage MCP servers.
- Provider errors/retries/abort: `provider-error`, `provider-error-after-reply`, `retry-exhausted`, `aborted-turn`.
- File changes, subagents, todos, status widgets: `edit-files`, `subagents`, `todos`, `ui-status-widgets`.
- Composer/editor/question previews: `ui-input`, `ui-editor`, `ui-question-preview`.
- Rich transcript, context, sessions, slash commands, steer queue: `rich-content`, `transcript-entries`, `context-high`, `session-tree`, `long-history`, `slash-commands`, `steer-queue`.

`media --reduce-motion off` clears only the harness override; operating-system and app-level reduce-motion settings stay active. `state` reports the effective media values and active override values.

## Fake-pi scenario guide

Pass a scenario to `start --scenario <name>`:

| Scenario | Use it to inspect |
|---|---|
| `hello-world` (default) | Basic chat and a completed assistant response. |
| `tool-call` | One tool call, execution progress, and result. |
| `with-thinking` | Reasoning content followed by a final answer. |
| `slow-stream` | Incremental streaming and in-progress UI. |
| `huge-output` | Long responses, scrolling, and large-output handling. |
| `parallel-tools` | Multiple tool calls and concurrent execution. |
| `compaction` | Compaction start and completion states. |
| `crash-mid-stream` | A fake-pi crash during streaming and recovery UI. |
| `malformed-line` | Malformed protocol input and error resilience. |
| `retry-then-success` | A transient failure, retry status, and success. |
| `ui-confirm` | An extension confirmation dialog. |
| `ui-select-timeout` | An extension selection dialog and timeout behavior. |

## Hard safety rules

- Use only `pf-harness` to start or stop harness processes. Never kill a process by name or kill a PID that the harness does not own.
- Never access or modify the user's `~/.piframe` or `~/.piframe-dev`.
- Never run `flutter build windows --release`; the user's running Release executable lives there.
- If harness startup refuses because a non-harness Debug `PiFrame.exe` is running, tell the user. Do not kill it.
- Use real screenshots from the actual Flutter app. Never fabricate or mock PiFrame UI.
- Do not commit `scratch/harness/` PNGs or regenerated `docs/design-evidence/` captures.

## Troubleshooting

- Check `pnpm harness status` and inspect recent output with `pnpm harness logs`.
- The first Windows build can take a while; let it finish.
- If a screenshot is black, wait for the app to settle and capture again.

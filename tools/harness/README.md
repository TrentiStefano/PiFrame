# PiFrame developer harness

Runs an isolated desktop PiFrame build, drives the app through `ext.piframe.*` Dart VM extensions, and saves real app screenshots. It uses no additional npm packages (Node 22+ required).

From the repository root:

```sh
pnpm harness start [--scenario hello-world] [--seed] [--size 1280x800] [--device windows|macos|linux] [--run name] [--no-daemon-build] [--real-pi]
pnpm harness seed [--run name]
pnpm harness scenarios
pnpm harness scenario <name> [--run name]
pnpm harness status [--run name]
pnpm harness call <extension> [json-params] [--run name]
pnpm harness tap <selector> [--run name]
pnpm harness tapAt <x> <y> [--run name]
pnpm harness rightClick <selector> [--run name]
pnpm harness doubleTap <selector> [--run name]
pnpm harness longPress <selector> [--run name]
pnpm harness drag <selector> <dx> <dy> [--run name]
pnpm harness hover <selector> [--run name]
pnpm harness type <text> [--into selector] [--run name]
pnpm harness key <name> [--ctrl --shift --alt --meta] [--run name]
pnpm harness scroll <selector> <dy> [--run name]
pnpm harness tree [--filter text] [--limit N] [--depth N] [--run name]
pnpm harness media [--text-scale 1.5] [--reduce-motion on|off] [--brightness light|dark] [--reset] [--run name]
pnpm harness state [--run name]
pnpm harness resize <width>x<height> [--run name]
pnpm harness shot [label] [--out path] [--run name]
pnpm harness reload|restart|rebuild [--daemon] [--run name]
pnpm harness logs [--lines 100] [--run name]
pnpm harness stop [--run name | --all]
```

Each run stores its isolated `PI_FRAME_HOME` under `~/.piframe-harness/<run>` (Windows: the user's home directory). Screenshots default to `scratch/harness/<run>/`. The default run is `default`.

Selectors use `key:<key>` for a widget key, `text:<text>` for visible text, and plain text as a text selector. Add `#N` for a specific matching index (for example `text:New session#2`). Dart VM extension parameter values are strings; this CLI JSON-encodes non-string values before sending them. `call` accepts a JSON object and prints the extension result. Tree entries retain covered rows, include button tooltips/labels, and report `truncated` when `--limit` or `--depth` caps traversal.

## Seed data and scenarios

`pnpm harness seed` creates isolated fixtures under that run's harness home; `pnpm harness start --seed` seeds before startup. It creates a dirty Git workspace (`fixtures/workspace`) with a staged, unstaged, and untracked change plus `feature/demo`, a second repository, five Pi session JSONL files (one with 150 messages and a linked `worker#…` child), one pinned session, and two MCP server entries. Seeding is repeatable. Git fixtures are skipped and reported when Git is unavailable. The seed command writes only under the safety-checked harness home.

`pnpm harness scenarios` lists the fake-pi scenario catalog. `pnpm harness start --scenario <name>` chooses the initial scenario. `pnpm harness scenario <name>` validates and changes the run's control file without restarting the app; fake-pi reads it on each prompt, so the next prompt uses the new scenario.

Examples:

```sh
pnpm harness start --seed --scenario edit-files
pnpm harness tree --filter notes.md --limit 80 --depth 12
pnpm harness scenario provider-error-after-reply
pnpm harness media --text-scale 1.4 --reduce-motion on --brightness dark
pnpm harness media --reset
pnpm harness drag key:sessions-sidebar-divider 80 0
pnpm harness tapAt 640 400
pnpm harness rightClick text:notes.md
```

Scenario user messages echo the prompt you send (`{{prompt}}`) with the current time (`{{now}}`).

In Git Bash on Windows, set `MSYS_NO_PATHCONV=1` before `pnpm harness type "/"`; otherwise the shell rewrites `/` to `C:/Program Files/Git/`.

Media overrides exist only in harness mode. `reduce-motion off` clears the harness request; OS and app reduce-motion preferences remain active. `state` reports the effective media values and current harness overrides.

## Feature → how to reach it

- Git Changes, file rows, staged/unstaged diffs: `start --seed`, open the seeded workspace, then `tree --filter notes.md`.
- Session list, pinned sessions, long-history paging, worker child: `start --seed`, then open the Sessions sidebar and select `Long history paging` or `Workspace planning`.
- MCP configuration: `start --seed`, Settings → Pi CLI → Manage MCP servers.
- Session tree / subagents: choose `session-tree` or `subagents`; seed also includes a linked `worker#fixture-child` session.
- Composer focus, editor/input states, question previews: use `ui-input`, `ui-editor`, `ui-question-preview`.
- Provider failures, retry exhaustion, aborts: use `provider-error`, `provider-error-after-reply`, `retry-exhausted`, `aborted-turn`.
- File edits, Todos, status widgets, rich content, transcript entries, high context, slash commands, and steer queue: use `edit-files`, `todos`, `ui-status-widgets`, `rich-content`, `transcript-entries`, `context-high`, `slash-commands`, and `steer-queue`.
- Review Changes: `start --seed`, open `Workspace implementation`, `scenario edit-files`, send a prompt, then `tap key:review-changes-btn`. fake-pi writes files only in folders that contain `.fake-pi-writable` (the seeded repositories do).
- Packages, Agents, MCP: fake-pi answers `pi list/install/remove/update` and `pi mcp list`, and a fake npm (`<home>/node_modules/npm/bin/npm-cli.js`) answers update checks offline. `pi-subagents` reports an update, so the startup update banner also appears.
- Text scale, reduced motion, brightness: `media`.
- Pane resizing and context menus: `drag key:sessions-sidebar-divider 80 0`, `rightClick text:<file name>`.
- Existing protocol coverage: `hello-world`, `tool-call`, `with-thinking`, `slow-stream`, `huge-output`, `parallel-tools`, `compaction`, `crash-mid-stream`, `malformed-line`, `retry-then-success`, `ui-confirm`, `ui-select-timeout`.

Safety model: by default, the harness creates a local fake-Pi launcher and sets `PI_FRAME_PI_PATH` to it; it never copies the user's PiFrame config. It sets `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR` beneath the harness home, and isolates `HOME`/`USERPROFILE`, preventing access to the user's normal Pi sessions. `--real-pi` disables fake-Pi enforcement and prints a loud warning; the Pi process still receives the isolated harness home and session directory. Process cleanup only targets supervisor/Flutter PIDs recorded as owned by that run and the daemon PID in that run's `runtime/daemon.json`; it never kills by process name. On Windows, the CLI refuses to launch against an already-running `apps/pi_frame/build/windows/x64/runner/Debug/PiFrame.exe` outside its own process tree.

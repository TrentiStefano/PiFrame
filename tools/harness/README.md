# PiFrame developer harness

Runs an isolated desktop PiFrame build, drives the app through `ext.piframe.*` Dart VM extensions, and saves real app screenshots. It uses no additional npm packages (Node 22+ required).

From the repository root:

```sh
pnpm harness start [--scenario hello-world] [--size 1280x800] [--device windows|macos|linux] [--run name] [--no-daemon-build] [--real-pi]
pnpm harness status [--run name]
pnpm harness call <extension> [json-params] [--run name]
pnpm harness tap <selector> [--run name]
pnpm harness hover <selector> [--run name]
pnpm harness type <text> [--into selector] [--run name]
pnpm harness key <name> [--ctrl --shift --alt --meta] [--run name]
pnpm harness scroll <selector> <dy> [--run name]
pnpm harness tree [--filter text] [--run name]
pnpm harness state [--run name]
pnpm harness resize <width>x<height> [--run name]
pnpm harness shot [label] [--out path] [--run name]
pnpm harness reload|restart|rebuild [--daemon] [--run name]
pnpm harness logs [--lines 100] [--run name]
pnpm harness stop [--run name | --all]
```

Each run stores its isolated `PI_FRAME_HOME` under `~/.piframe-harness/<run>` (Windows: the user's home directory). Screenshots default to `scratch/harness/<run>/`. The default run is `default`.

Selectors use `key:<key>` for a widget key, `text:<text>` for visible text, and plain text as a text selector. Add `#N` for a specific matching index (for example `text:New session#2`). Dart VM extension parameter values are strings; this CLI JSON-encodes non-string values before sending them. `call` accepts a JSON object and prints the extension result.

Safety model: by default, the harness creates a local fake-Pi launcher and sets `PI_FRAME_PI_PATH` to it; it never copies the user's PiFrame config. It sets `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR` beneath the harness home, and isolates `HOME`/`USERPROFILE`, preventing access to the user's normal Pi sessions. `--real-pi` disables fake-Pi enforcement and prints a loud warning; the Pi process still receives the isolated harness home and session directory. Process cleanup only targets supervisor/Flutter PIDs recorded as owned by that run and the daemon PID in that run's `runtime/daemon.json`; it never kills by process name. On Windows, the CLI refuses to launch against an already-running `apps/pi_frame/build/windows/x64/runner/Debug/PiFrame.exe` outside its own process tree.

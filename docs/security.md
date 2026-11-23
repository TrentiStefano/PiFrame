# PiFrame Security Baseline and Threat Model

This document describes the security architecture, the defenses in place and the threat model for the **PiFrame** runtime and the `pi-agentd` daemon.

---

## 1. Threat model and trust boundaries

The `pi-agentd` daemon is a local, high-privilege service: it can work with the file system and run the Pi CLI (`pi --mode rpc`). Its attack surface must therefore stay limited to the local user of the machine and to remote devices the user has explicitly authorized.

### Network boundary
- **Loopback only (`127.0.0.1`)**: both HTTP/WebSocket servers (local and remote) bind only to `127.0.0.1`. The daemon never opens a public interface (`0.0.0.0` or a LAN IP).
- **Two physical listeners**:
  - **Local listener** (`httpServer`): reserved for the Flutter desktop app and the web interface opened on loopback.
  - **Dedicated remote listener** (`remoteHttpServer`): a separate listener on its own port, which the tunnel (Cloudflare or custom) forwards to. Remote origin is decided by the socket the connection arrives on, not by HTTP headers that a client could forge.

---

## 2. Authentication and token handling

Decision record: [ADR 0011](adr/0011-authentication-and-tokens.md).

- **Master token entropy**: every daemon instance generates a random 256-bit token at startup (`crypto.randomBytes(32).toString('hex')`).
- **Strict master token segregation (H2)**:
  - The master token is accepted **only** on the local listener (`127.0.0.1:<localPort>`).
  - On the dedicated remote listener, any attempt to authenticate with the master token is rejected: the WebSocket closes at once (`4003`), or HTTP returns `401 Unauthorized`.
  - The `/api/session-bootstrap` endpoint on the remote listener never returns the master token.
- **Runtime files**:
  - The master token is stored in `~/.piframe/runtime/daemon.token` with owner-only permissions (`0600`).
- **Constant-time comparison**: token checks use `crypto.timingSafeEqual` (`timingSafeEqualStrings`) to prevent timing attacks.
- **No tokens in URLs or query strings**: tokens and secrets never travel as HTTP query parameters, so they cannot leak into server or proxy logs or the Referer header.

---

## 3. PCP protocol and WebSocket security (F2, F4)

- **Authenticated handshake**:
  - A WebSocket connection that does not complete the `hello` handshake with valid credentials within 5 seconds is closed with code `4001` or `4003`.
- **Separate rate-limit buckets (H3)**:
  - Authentication failures on the remote listener (`r:<ip>`) and on the local listener (`l:<ip>`) are counted in separate buckets.
  - Brute-force attempts or floods of unauthenticated WebSocket connections on the remote tunnel can never block or slow down the local desktop app.
- **Host and Origin validation**:
  - On the local listener, the `Host` header must be a loopback address; any reverse-proxy header (`X-Forwarded-For`, `CF-Connecting-IP`, `Via` and so on) returns `403 Forbidden` at once.
  - On the remote listener, the `Host` header and any `Origin` must match the authorized hostname of the active tunnel.
- **Concurrency and frame limits**:
  - At most 10 concurrent remote connections in the handshake phase.
  - At most 200 commands per second per WebSocket connection.
  - Maximum WebSocket frame size: 4 MiB (larger frames close the connection with `4009`).

---

## 4. Web hosting and Content Security Policy

Decision record: [ADR 0013](adr/0013-local-web-hosting.md).

- **Dynamic Content Security Policy (M4)**:
  - Local listener: a strict CSP that allows connections only to loopback (`ws://127.0.0.1:*`, `http://127.0.0.1:*`).
  - Remote listener: a CSP with `connect-src 'self' https://<tunnelHost> wss://<tunnelHost>`, plus `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
- **Security headers**:
  - `X-Frame-Options: DENY` (anti-clickjacking)
  - `Referrer-Policy: no-referrer`
  - `X-Content-Type-Options: nosniff`
  - `Cache-Control: no-store` on every API response
- **Bootstrap cookies**:
  - Local listener: `Set-Cookie: pcp_token=<token>; Path=/; HttpOnly; SameSite=Strict`.
  - Remote listener: the device cookie `Set-Cookie: pcp_device_token=<token>; Path=/; HttpOnly; SameSite=Lax; Secure`. The remote listener never issues a master cookie.
- **Path traversal prevention**:
  - The static file handler normalizes paths and checks that `path.relative(staticDir, targetPath)` does not start with `..`.
  - The blob endpoints (`/api/blobs/:blobId`) use `path.basename`.

---

## 5. Privacy and no remote telemetry

Decision record: [ADR 0016](adr/0016-zero-remote-telemetry.md).

- **No remote data collection**:
  - PiFrame includes no SDK or endpoint for telemetry, analytics or crash reporting to third-party servers.
  - All logs stay on the user's local file system (`~/.piframe/runtime/daemon.log`).
- **Automatic secret redaction**:
  - Every export feature redacts tokens and API keys (`[REDACTED]`).

---

## 6. Safe remote access and device pairing

Remote access lets you use the PiFrame daemon from a phone or an external browser. Its architecture is locked down as follows.

### 1. Opt-in by default
No remote listener, tunnel process or port starts unless the user turns the option on in the settings. At system startup, auto-start does not create short-lived pairing secrets until the user asks for one.

### 2. One-time pairing through the URL fragment (`#pair=...`)
- **High-entropy secret**: pairing generates a random 256-bit secret (`pair_tok_<base64url>`). There is no short 6-digit PIN, which removes the risk of brute force and social engineering.
- **URL fragment (M2)**: the secret travels in the link hash (`https://tunnel.example.com/#pair=<secret>`), so it is never sent to web servers or proxies as a query string and never appears in HTTP logs.
- **Dedicated web bootstrap script (`pair_bootstrap.js`)**: the web client reads the fragment before the app starts, clears the address bar and browser history at once with `history.replaceState`, and exchanges the secret with a JSON POST to `/api/remote/pair`.
- **Global destruction after repeated failures**: after 5 wrong attempts from any client or IP, the whole pairing secret is destroyed and revoked (global anti-brute force).
- **Per-IP rate limit**: 5 failed attempts from one IP block it for 15 minutes.

### 3. Device credentials and hashing
- **No plain-text tokens on disk (H1)**: the device database (`remote_devices.json`) stores only the SHA-256 hash of each device secret. The file is created with `0600` permissions.
- **Sliding expiry and device limit**: device tokens last 30 days, renewed on every verified use. At most 10 devices can be registered at the same time.
- **Instant revocation**: when the desktop user revokes a device, its open WebSocket connections close at once with code `4003`.

### 4. Permission model: view vs control mode (C2)
Every paired device works in a mode the desktop assigns:
- **`view` mode (default and recommended)**:
  - Allows inspection only: sessions, statistics, the conversation tree, workspace diffs, file reads and branch listing (`workspace.listBranches`).
  - **Emergency permissions**: includes `agent.abort` and `agent.interrupt`, so the user can stop the agent from a phone when needed.
  - **Write block**: every write command (`agent.prompt`, `agent.steer`, `workspace.saveFile`, `workspace.gitAction`, `workspace.switchBranch`, continuing a session) is rejected with `REMOTE_FORBIDDEN`.
- **`control` mode**:
  - Needs explicit confirmation in a warning dialog on the desktop. It includes write and repository commands (`workspace.saveFile`, `workspace.gitAction`, `workspace.switchBranch`), which are still bound by `assertWorkspaceWritable`: they cannot run while the agent is working or on read-only sessions.
  - **Risk note**: a device in `control` mode can send prompts and run commands with the privileges of the operating-system user.

### 5. Default-deny allowlist in the dispatcher (C1)
All administrative and configuration commands are blocked for remote connections:
- `remote.*` (including `remote.start`, `remote.setOptions`, `remote.generatePairing`, `remote.revokeDevice`) → `REMOTE_FORBIDDEN`.
- `daemon.getConfig` and `daemon.setConfig` → `REMOTE_FORBIDDEN`.
- `pi.packages.*` → `REMOTE_FORBIDDEN`.
- `pi.agents.*` (`pi.agents.get`, `pi.agents.update`) → `REMOTE_FORBIDDEN`.
- `system.metrics.*` (`system.metrics.subscribe`, `system.metrics.unsubscribe`) → `REMOTE_FORBIDDEN`.
- `daemon.setConfig` refuses direct changes to the `remote` and `web` sections even from local connections (`CONFIG_INVALID`).

### 6. File-system confinement for remote commands (M7)
Creating sessions remotely (`session.create` or `session.open {cwd}`) requires the `cwd` to be inside the directory of a workspace that is already known and open locally.

### 7. Safe tunnel provider execution (M5, M8)
- The custom tunnel command (`customTunnelCommand`) runs **without a shell** (`shell: false`), with manual argument parsing (argv), which removes any risk of shell injection (`&`, `|`, `;`).
- The custom URL (`customTunnelUrl`) is strictly validated: it must use `https://`, cannot contain credentials and cannot point to loopback addresses.
- On shutdown, the whole tunnel process tree is terminated cleanly (`taskkill /T /F` on Windows, a process-group signal on POSIX).

### 8. System metrics and hardware monitoring
Sampling of host resources (CPU, memory, the disk volume of `homedir`, GPU) is designed to keep energy use low and to make sure no telemetry reaches remote devices:
- **Local only**: `system.metrics.subscribe` and `system.metrics.unsubscribe` are rejected with `REMOTE_FORBIDDEN` for every remote connection (in both `view` and `control` mode).
- **Gated on active subscriptions**: with zero subscribers, no timer runs, no file-system or kernel reads happen and no child process is alive.
- **Allowed external tools, no user input**:
  The child processes started for GPU detection are limited to a closed set:
  - `nvidia-smi` (fixed arguments: `-L` for the probe; `--query-gpu=...` in CSV format for polling).
  - `typeperf` on Windows (fixed argument: `\GPU Engine(*)\Utilization Percentage` with interval `-si 1`).
  - `ioreg` on macOS (fixed arguments: `-r -d 1 -w 0 -c IOAccelerator`, with an 800 ms timeout).
  - Linux reads `/sys/class/drm/` directly without starting any binary.
  All child processes run with `shell: false`, `windowsHide: true` and fixed arguments hardcoded in the source, with no input from the client. They are terminated as soon as the last subscription is removed or the daemon shuts down.

### 9. Subagent configuration and runtime extensions (Pi subagents)
Subagent settings and context limits are handled with strict integrity and isolation safeguards:
- **Local only**: `pi.agents.get` and `pi.agents.update` are rejected with `REMOTE_FORBIDDEN` for every remote device. Pi and subagent configuration can be read or changed only through local connections.
- **Atomic writes and a compatible lockfile**: changes to `~/.pi/agent/settings.json`, `~/.pi/agent/subagents.json` and `~/.piframe/subagent-context.json` take a `<file>.lock` directory lock that is fully compatible with Pi's `proper-lockfile` (stale-lock detection after 10 seconds). Before any write, a backup copy `settings.json.piframe-backup` is created. The write goes to a temporary file in the same directory with restrictive permissions and is then renamed atomically. If the configuration file is not valid JSON, the operation fails closed (`AGENTS_CONFIG_UNREADABLE`) and leaves the file untouched.
- **Extension generation and isolation**: the runtime extension for subagent context limits (`~/.piframe/runtime/subagent-context-limit.mjs`) is generated as fully self-contained code, with no external dependencies and no network access. It is loaded only in subagent child processes through Pi's native `subagentOnlyExtensions` setting, and it only adjusts `contextWindow` with `pi.setModel` when the subagent session starts.

### 10. Read-only side conversations
Short-lived side conversations let the user consult a secondary assistant limited to read-only tools, working on an immutable snapshot of the main conversation:
- **File-system isolation, no writes to Pi sessions**: side workers start with `--no-session` and create no file in Pi's session directory (`~/.pi/agent/sessions/`). The snapshot of the main session is rendered as Markdown and saved only in `~/.piframe/runtime/side/<sideId>/context.md` (directory created with `0700`, file with `0600`), and it is always deleted when the side thread closes or the daemon shuts down. The main session file stays byte-for-byte identical before, during and after every side operation.
- **No disk spill, in-memory events only**: side conversation events are never recorded in the main session journal or written to disk. They are kept only in an in-memory ring buffer for the lifetime of the daemon, so clients can reconnect.
- **Strict tool restriction (allowlist `{read, grep, find, ls}`)**: side workers start with `--tools read,grep,find,ls`, `--no-mcp`, `--no-extensions`, `--no-skills`. Tools that can change files (`bash`, `edit`, `write`) are fully blocked. Right after startup the daemon queries `get_state`: if it reports active tools outside the allowlist `{read, grep, find, ls}`, the worker is terminated at once with `SIDE_UNSAFE_TOOLS`. Pi 1.5.0 does not include the tool list in `get_state`, so this check is inactive today and the read-only guarantee rests on the startup flags (`--tools` is an exact allowlist and `--no-extensions` excludes tools registered by packages).
- **Strict RPC transport allowlist**: the `SideTransport` wrapper blocks every RPC command other than `prompt`, `abort` and `get_state` (rejected with `SIDE_RPC_BLOCKED`), which stops any attempt to run `bash`, `switch_session`, `fork` or other disallowed operations.
- **Remote permissions, view vs control**: opening (`side.open`) and prompting (`side.prompt`) require `control` mode from remote devices (rejected with `REMOTE_FORBIDDEN` in `view` mode). Aborting (`side.abort`) and closing (`side.close`) are allowed in `view` mode too, so a phone can stop a side thread in an emergency.
- **Immutable side stream**: every command other than a subscription (`session.attach` or `session.detach`) sent to a side stream (`sessionId = side_<ulid>`) is blocked with `SIDE_STREAM_READ_ONLY`.
- **Concurrency limits, idle timeout and lifecycle**:
  - At most 1 open side thread per parent session (further open calls return the active thread).
  - At most 4 side threads active at the same time on the whole system (`SIDE_LIMIT_REACHED`).
  - The worker shuts down automatically after 10 minutes of inactivity (`reason: 'idle'`).
  - The side thread closes at once if the parent session is closed or deleted (`reason: 'parentClosed'`).
  - Full cleanup and process termination when the daemon shuts down (`reason: 'shutdown'`).
  - No child command ever runs with `shell: true`, and the daemon makes no external network calls.

---

## 7. Remaining limitations and operational recommendations

- **Cloudflare trust boundary**: with Cloudflare's free quick tunnels (`cloudflared`), TLS terminates on Cloudflare's edge servers before reaching the local daemon. For end-to-end encryption without a commercial intermediary, use **Tailscale Serve** or a private VPN inside your own mesh network.
- **Devices in control mode**: granting `control` mode to a device is the same as granting terminal access as the local user. Keep devices in `view` mode unless you really need to act from a phone.

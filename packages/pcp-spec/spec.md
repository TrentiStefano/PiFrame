# PCP/1: Pi-Crust Protocol Specification (Version 1)

This document is the normative specification of the Pi-Crust Protocol (PCP/1).
PCP/1 defines the bidirectional, asynchronous, message-based protocol used between **pi-agentd** (the background daemon) and **Pi-Crust** clients (Flutter desktop and web).

---

## 1. Transport Layer

- **Underlying Protocol:** WebSocket (RFC 6455) over TCP loopback (`127.0.0.1`).
- **Endpoint:** `ws://127.0.0.1:<port>/api/ws`
- **Frame Format:** Text frames only (`opcode: 0x1`).
- **Framing Rule:** Exactly one valid JSON object per text frame.
- **Max Frame Size:** 4,194,304 bytes (4 MiB). Larger payloads (e.g. large images) use `POST /api/blobs`.
- **Heartbeat:** The daemon sends a ping message every 15 seconds; client must respond with pong within 10 seconds. Inactivity without pong causes disconnect with code `4008`.
- **Close Codes:**
  - `4001`: Handshake timeout (no valid `hello` within 5 seconds).
  - `4002`: Protocol version unsupported.
  - `4003`: Authentication failed (invalid or missing bearer token).
  - `4004`: Origin rejected (disallowed browser origin).
  - `4008`: Heartbeat timeout.
  - `4009`: Slow client / backpressure buffer exceeded.
  - `4010`: Daemon shutting down cleanly.

---

## 2. Common Envelope

Every message sent across the WebSocket conforms to the common envelope:

```json
{
  "protocol": 1,
  "kind": "event",
  "id": "evt_01HZ123456789ABCDEF0123456",
  "ts": 1726640000123,
  "sessionId": "s_01HZ987654321ABCDEF0123456",
  "seq": 481,
  "type": "text.delta",
  "payload": {}
}
```

### Fields
- `protocol` (integer, required): Always `1` for PCP/1.
- `kind` (string, required): One of:
  - `hello`, `welcome`
  - `command`, `ack`, `result`
  - `event`, `snapshot`, `error`
  - `ping`, `pong`
- `id` (string, required): Globally unique ULID/UUID assigned by sender.
- `ts` (integer, required): Unix timestamp in milliseconds assigned by sender.
- `sessionId` (string, optional): Required for session-scoped messages. Non-session messages (daemon health, index updates) use `"@daemon"` or omit this field.
- `seq` (integer, optional): Strictly monotonic per-session sequence integer assigned by the daemon event journal. Present on `kind="event"` and `kind="snapshot"`.
- `type` (string, required): Semantic message type.
- `payload` (object, required): Payload dictionary; never `null`.

### Invariants
1. **Extensibility:** Unknown `type` values must be safely logged and ignored by the receiver, never causing fatal deserialization errors.
2. **Monotonicity:** `seq` increases strictly by 1 per session. Clients discard duplicate `seq <= lastAppliedSeq` and trigger re-attach if `seq > lastAppliedSeq + 1`.

---

## 3. Handshake & Authentication

### 3.1 Handshake Flow
1. Client connects via WebSocket to `ws://127.0.0.1:<port>/api/ws`.
2. Within 5.0 seconds, client sends `kind: "hello"`:
   ```json
   {
     "protocol": 1,
     "kind": "hello",
     "id": "msg_01...",
     "ts": 1726640000000,
     "type": "connection.hello",
     "payload": {
       "token": "<256-bit base64url bearer token>",
       "client": { "name": "pi-crust", "version": "0.1.0", "platform": "windows" },
       "encoding": "json",
       "capabilities": ["replay.v1", "ui.claim.v1", "workspace.v1"]
     }
   }
   ```
3. Daemon verifies token in constant time and checks origin.
4. On success, daemon replies with `kind: "welcome"`:
   ```json
   {
     "protocol": 1,
     "kind": "welcome",
     "id": "msg_02...",
     "ts": 1726640000050,
     "type": "connection.welcome",
     "payload": {
       "clientId": "c_01...",
       "daemon": { "version": "0.1.0", "startedAt": 1726639000000, "pid": 1234 },
       "pi": { "path": "node .../cli.js", "version": "0.85.1", "supported": true },
       "capabilities": ["replay.v1", "ui.claim.v1", "workspace.v1"],
       "limits": { "maxFrameBytes": 4194304, "journalMaxEvents": 2000 }
     }
   }
   ```

---

## 4. Commands, Ack, and Results

Client sends:
```json
{
  "protocol": 1,
  "kind": "command",
  "id": "msg_cmd_01...",
  "ts": 1726640000100,
  "commandId": "cmd_01...",
  "sessionId": "s_01...",
  "type": "agent.prompt",
  "payload": { "message": "Refactor auth module" }
}
```

Daemon returns an `ack` immediately:
```json
{
  "protocol": 1,
  "kind": "ack",
  "id": "msg_ack_01...",
  "ts": 1726640000105,
  "commandId": "cmd_01...",
  "sessionId": "s_01...",
  "type": "command.ack",
  "payload": { "state": "accepted" }
}
```

Followed by `result`:
```json
{
  "protocol": 1,
  "kind": "result",
  "id": "msg_res_01...",
  "ts": 1726640000150,
  "commandId": "cmd_01...",
  "sessionId": "s_01...",
  "type": "command.result",
  "payload": { "state": "completed", "data": {} }
}
```

### Idempotency
- `commandId` is cached for 10 minutes.
- Re-sending an identical `commandId` returns `state: "deduplicated"` with original data without re-executing.

### 4.1 Workspace commands

Workspace commands require `sessionId`; daemon derives repository root from that registered session's cwd. Client-supplied cwd is not accepted. Paths are repository-relative and must not traverse outside the Git root.

- `workspace.listFiles` payload `{}` → `{rootPath, files:[{path,sizeBytes}], truncated}`.
- `workspace.readFile` payload `{path}` → `{rootPath,path,content,revision,sizeBytes}`. `revision` is SHA-256 of file bytes. Only UTF-8 text files up to 1 MiB are supported; binary and larger files return explicit errors.
- `workspace.saveFile` payload `{path,content,revision}` → `{path,revision}`. Revision is required and stale revisions are rejected; save uses an atomic same-directory replacement.
- `workspace.gitAction` payload `{action,paths,expectedStagedPaths?,message?}` → `{status}`. `action` is `stage`, `unstage`, `commit`, or `discard`. Paths are explicit repository-relative paths. `commit` requires non-empty `message`, and both `paths` and `expectedStagedPaths` must exactly match current staged paths before commit.

Repository writes (`saveFile` and every Git action) are rejected for read-only sessions or while the Pi worker is active/streaming. `workspace.refresh` keeps existing Git status fields and includes `staged` / `unstaged` flags with index/worktree status codes per path.

### 4.2 Pi package commands

These authenticated local-daemon commands operate on Pi's user-level package settings and invoke the discovered Pi CLI without a shell. They do not accept a caller-supplied package directory or project scope.

- `pi.packages.list` payload `{}` → `{packages:[{source,name,version,pinnedVersion}]}`.
- `pi.packages.update` payload `{source}` → `{output}`; delegates to `pi update <source>`.
- `pi.packages.remove` payload `{source}` → `{output}`; delegates to `pi remove <source>`.
- `pi.packages.pin` payload `{source,version}` → `{output,source}`; accepts npm package sources only and delegates to `pi install npm:<name>@<semver>`.

Mutating package commands require explicit confirmation in the UI. Pi remains owner of package settings and installation directories. Package code can execute in Pi's process; removal, update and pin controls must show package identity and scope before confirmation. Project-local resources remain governed by Pi's project-trust policy and are not managed by these user-scope commands.

---

## 5. Normalized Event Types

See Section 4.7 of the implementation plan for complete event catalogue:
- `session.status`, `run.started`, `run.ended`, `run.settled`, `turn.started`, `turn.ended`
- `message.started`, `message.completed`, `text.started`, `text.delta`, `text.completed`
- `thinking.started`, `thinking.delta`, `thinking.completed`
- `toolcall.started`, `toolcall.argsDelta`, `toolcall.completed`
- `tool.started`, `tool.progress`, `tool.completed`
- `queue.changed`, `compaction.started`, `compaction.ended`, `retry.started`, `retry.ended`
- `ui.request`, `ui.claimed`, `ui.resolved`, `ui.notify`, `ui.status`, `ui.widget`, `ui.editorText`, `ui.title`
- `workspace.changed`, `worker.diagnostic`, `worker.crashed`, `journal.gap`, `session.indexChanged`, `daemon.configChanged`

---

## 6. Attachment, Replay & Snapshots

When attaching to a session (`session.attach{ lastSeq }`):
1. `lastSeq == null`: Daemon sends full authoritative `snapshot` (seq = currentSeq), then live events.
2. `lastSeq >= journal.minSeq - 1 && lastSeq <= currentSeq`: Daemon sends `ack{ state: "resume" }` followed by replay events `lastSeq+1 ... currentSeq`, then live stream.
3. `lastSeq < journal.minSeq - 1`: Journal gap detected. Daemon sends `snapshot`, emits `journal.gap{ fromSeq, toSeq }`, then live stream.
4. `lastSeq > currentSeq`: Reset. Daemon sends `snapshot` and `journal.reset`.

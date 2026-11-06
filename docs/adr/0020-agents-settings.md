# ADR 0020: Subagent Configuration, Locking, and Context Limits

- **Status:** Accepted
- **Confirmation Date:** 2026-11-06

## Context

PiFrame users require the ability to discover, inspect, and configure subagents, session defaults, and subagent context limits without directly hand-editing Pi configuration files or risking concurrent write corruption.

### Background Facts (Verified in Codebase & Pi Runtimes)
1. **Installed Subagent Package (`pi-subagents` by nicobailon):**
   - Installed at `~/.pi/agent/npm/node_modules/pi-subagents`.
   - Agent definitions reside in `agents/*.md` with YAML frontmatter.
   - Builtin agent names are defined in `src/agents/builtin-names.js` (`BUILTIN_AGENT_NAMES`: advisor, claude-code, claude-code-writer, codex-exec, codex-exec-writer, cursor-agent, cursor-agent-writer, delegate, evidence-auditor, oracle, researcher, reviewer, scout, worker).
   - Agent overrides are read by `pi-subagents` from `~/.pi/agent/settings.json` under `subagents.agentOverrides.<name>` with fields including `model` (e.g. `'provider/id'` optionally `':thinking'`), `thinking` (`off`|`minimal`|`low`|`medium`|`high`|`xhigh`|`max`), and `subagentOnlyExtensions` (array of absolute file paths).
   - Global subagent defaults are read from `subagents.defaultModel` and `subagents.defaultThinking`.
2. **Alternative Subagent Package (`@tintinweb/pi-subagents`):**
   - Alternative community package with builtin agents `general-purpose`, `Explore`, and `Plan`.
   - Configured via `~/.pi/agent/subagents.json` with key `fallbackSubagent`.
   - Does not support per-agent overrides in `settings.json`.
3. **Pi Native Session Defaults:**
   - Pi reads top-level keys `defaultProvider`, `defaultModel`, `defaultThinkingLevel` in `~/.pi/agent/settings.json` which apply to all new native sessions.
4. **Pi Settings Concurrency and Lack of RPC Settings Writer:**
   - Pi RPC exposes no settings write command (`get_state` and `get_available_models` are read-only).
   - Pi's internal `SettingsManager` manages mutations using a file lock via `proper-lockfile` (creating `<filePath>.lock` directory, with 10s stale detection and retry delays).
5. **Context Limit Seam in Subagents:**
   - Subagents are spawned in isolated child sessions where `<active_agent name="...">` is tagged in the initial system prompt (verified in `pi-subagents/src/runs/shared/child-launch.js`).
   - Pi's `subagentOnlyExtensions` allows injecting a custom extension path specifically into child subagent runs.
   - Native Pi extension lifecycle hooks (`session_start` and `before_agent_start`) expose `ctx.model` and `pi.setModel`.

## Decision

Implement subagent discovery, validation, atomic locking, and context enforcement in the daemon (`apps/agentd/src/pi/agents/`):

1. **Protocol Commands (`pi.agents.v1`):**
   - `pi.agents.get` (payload `{ cwd? }`): target `@daemon`, strictly local-only (returns `REMOTE_FORBIDDEN` for remote connections). Discovers installed subagent packages, agent profiles, session defaults, subagent defaults, available models from Pi, and supported thinking levels.
   - `pi.agents.update` (payload `{ changes: [...] }`): target `@daemon`, strictly local-only. Performs atomic mutations with validated inputs.

2. **Auto-Detection & Priority Hierarchy:**
   - Discovers installed packages from `settings.json` `packages` and filesystem directories (`~/.pi/agent/npm/node_modules/pi-subagents` and `@tintinweb/pi-subagents`).
   - Discovers agent files across package `agents/*.md`, user `~/.pi/agent/agents/*.md`, and project `.pi/agents/*.md`.
   - Agent definition priority: `builtin (0) < package (1) < user (2) < project (3)`. A user agent overrides a package builtin by name.
   - External CLI runners (frontmatter `runner: type: external-cli` or similar) are marked `editable: false`, `readOnlyReason: 'external CLI runner'`.
   - Tintinweb agents are marked `editable: false`, `readOnlyReason: 'tintinweb: edit agent file'`.
   - Project agents are marked `editable: false`, `readOnlyReason: 'project agent (read-only)'`.

3. **Validated Settings Writer with Pi-Compatible File Locking:**
   - Implements a mkdir-based lock `<file>.lock` strictly compatible with `proper-lockfile` 4.x (10s stale duration recovery, retry loop with backoff, throwing `AGENTS_CONFIG_LOCKED` on timeout).
   - Validates JSON format; if `settings.json` contains invalid JSON, fails closed with `AGENTS_CONFIG_UNREADABLE` without touching the file.
   - Preserves all unrelated keys, property ordering, file modes (POSIX permissions), and existing `agentOverrides` fields.
   - Automatically maintains a single backup file `settings.json.piframe-backup` before modification.
   - Performs atomic writes using same-directory temporary file write and rename.
   - Removes empty override objects that PiFrame emptied when removing overrides.
   - Applies identical discipline to `subagents.json` and `subagent-context.json`.
   - Serializes all updates in-process through a single queue to prevent daemon-level concurrency races.

4. **Context Limit via `subagentOnlyExtensions`:**
   - Generates a self-contained runtime extension at `~/.piframe/runtime/subagent-context-limit.mjs`.
   - On `session_start` and `before_agent_start`, parses `<active_agent name="...">` from the system prompt, reads the target limit from `~/.piframe/subagent-context.json`, and if the model has pricing tiers and `limit < model.contextWindow`, calls `pi.setModel({ ...model, contextWindow: limit })`.
   - When a context limit is set on an agent, the absolute extension path is added to `subagents.agentOverrides.<name>.subagentOnlyExtensions` (deduplicating existing paths). When cleared, the extension path is removed.

5. **Two Distinct Defaults:**
   - Session defaults: `defaultProvider`, `defaultModel`, and `defaultThinkingLevel` in `settings.json` governing new primary chat sessions.
   - Subagent defaults: `subagents.defaultModel` and `subagents.defaultThinking` in `settings.json` (or `fallbackSubagent` in `subagents.json` for tintinweb).

## Consequences

- Configuration file edits never corrupt Pi's native state or cause startup crashes.
- Subagent runs can respect exact context tiers without polluting main session settings or modifying Pi's installed binaries.
- Remote connections cannot read or mutate local configuration files, maintaining strict local security boundaries.

## Alternatives Rejected

- **Direct Import of Pi's `SettingsManager`:** Rejected. `SettingsManager` is not part of Pi's stable public SDK and importing internal dist modules couples PiFrame tightly to internal release packaging, transpilation formats, and path layouts.
- **Unvalidated Raw Edits:** Rejected. Allowing clients to write arbitrary fields to `settings.json` risks breaking Pi startup, setting unsupported model IDs, or stripping required options.
- **Inventing Non-Native Context Window Fields in `settings.json`:** Rejected. Pi and `pi-subagents` ignore unrecognized keys in `agentOverrides`. Using the official extension seam (`subagentOnlyExtensions`) guarantees runtime enforcement through Pi's native model-switching API.

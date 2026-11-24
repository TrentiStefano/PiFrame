# PiFrame

PiFrame is a desktop and web workbench for the Pi coding agent: a Flutter app talks to a local daemon, which runs Pi for each session. This glossary gives every core concept one name; use it in code, issues, tests and docs, and do not drift to the names under _Avoid_.

## Language

### System

**PiFrame app**:
The Flutter client (Windows, macOS, Linux, and a web build) that draws the UI and asks the daemon for everything else.
_Avoid_: GUI, frontend

**Client**:
One connection of the PiFrame app (a desktop window or a browser tab) to the daemon. Several clients can attach to the same session (ADR 0010).
_Avoid_: GUI, window, tab

**Daemon**:
The local background process that runs Pi workers, keeps their journals and serves the PiFrame app over PCP. Its executable is `pi-agentd` and its code lives in `apps/agentd`; neither is renamed, but in prose write "daemon" (ADR 0001, 0008, 0014).
_Avoid_: `pi-agentd` (except for the executable), `agentd` (except for the folder or package), background service, server, sidecar

**Pi**:
The upstream coding agent (`@earendil-works/pi-coding-agent`) that PiFrame drives; the user installs it separately and it owns models, tools and session history (ADR 0015).
_Avoid_: Pi CLI (when you mean the agent), the backend

**Pi worker**:
One `pi --mode rpc` process that the daemon starts and supervises for a session, stopped after an idle timeout (ADR 0009).
_Avoid_: worker (on its own), Pi process, agent process

**PCP**:
The PiFrame Communication Protocol (PCP/1): the versioned JSON message protocol between the daemon and clients over WebSocket on `127.0.0.1`, defined in `packages/pcp-spec` (ADR 0003, 0012). Spell it out on first use.
_Avoid_: PiFrame's local protocol, the API, the WebSocket protocol

**Normalized event**:
A PCP event the daemon builds from Pi's raw output, so clients never depend on Pi's own event format (ADR 0005).
_Avoid_: Pi event (that is Pi's raw output), message

### Sessions

**Session**:
One Pi conversation, stored by Pi as a session file and registered with the daemon under a PCP session id.
_Avoid_: chat (that is the pane), thread, conversation (on its own)

**Session file**:
Pi's own record of a session under `~/.pi/agent/sessions/`; Pi owns it and the daemon never writes it (ADR 0021).
_Avoid_: transcript file, history file

**Read-only session**:
A session that a Pi terminal has open at the same time, so PiFrame shows it but does not drive it.
_Avoid_: locked session, terminal session

**Run**:
The agent's work on one prompt, from `run.started` to `run.settled`; a run is made of one or more turns.
_Avoid_: job, generation

**Turn**:
One model reply inside a run, with the tool calls it makes, from `turn.started` to `turn.ended`.
_Avoid_: step (that is a part of a turn), round

**Steer**:
A message sent to the agent while a run is active, which redirects it without stopping the run.
_Avoid_: interrupt, inject

**Follow-up**:
A message queued while a run is active, sent to the agent only after the run ends.
_Avoid_: queued prompt, next message

**Steer queue**:
A session's pending steer and follow-up messages, which the user can edit, delete or clear before Pi takes them.
_Avoid_: message queue, prompt queue

**Compaction**:
Pi replacing older messages of a session with a summary to free room in the model's context window.
_Avoid_: summarization, truncation

**Context limit**:
The context window that PiFrame lets a session's or subagent's model use, at most the model's own maximum (ADR 0020).
_Avoid_: context tier (that is a model's pricing tier), context size

### Journal and replay

**Journal**:
The daemon's numbered record of a session's normalized events, kept so clients can reconnect without loss; it is never the authoritative history, which stays in the session file (ADR 0006, 0007).
_Avoid_: transcript, event log, history

**Spill**:
The append-only on-disk copy of a session's journal under `~/.piframe/journal/<sessionId>/`, which lets replay survive a daemon restart (ADR 0006).
_Avoid_: dump, cache, journal file

**Snapshot**:
The full current state of a session that the daemon sends when a client attaches for the first time or replay from the journal is not possible (ADR 0007).
_Avoid_: state dump, sync

**Replay**:
The daemon re-sending a session's journal events after the last sequence number a client saw, when it attaches again.
_Avoid_: resync, catch-up

### Agents

**Subagent**:
A background agent that the main agent starts in its own child session through a subagent package (`pi-subagents` or `@tintinweb/pi-subagents`) inside the Pi worker (ADR 0020).
_Avoid_: background agent, child agent, sub-agent

**Child session**:
The session file in which a subagent's conversation is recorded.
_Avoid_: sub-session, subagent session

**Workflow**:
A `SubagentWorkflow` run from `@tintinweb/pi-subagents`: a script that starts several subagents in phases.
_Avoid_: pipeline, job

**Task notification**:
The `<task-notification>` message that a subagent or workflow sends to the main agent when it settles, shown in the transcript as a card.
_Avoid_: subagent result, completion message

**Side conversation**:
A short-lived, read-only exchange with a separate Pi worker about a snapshot of a session, opened with `/btw` (or `/side`); it never changes the session or its journal (ADR 0021).
_Avoid_: side discussion, side thread, btw, side chat

### User interface

**Workspace**:
The project folder a session works in (its working directory, or its Git root), whose files and Git state PiFrame shows and edits.
_Avoid_: repo (on its own), project, workspace panel (that is the UI area)

**Workspace panel**:
The main area of the window where a session's panes sit side by side: the chat pane and its companion panes.
_Avoid_: workspace (on its own), Area di lavoro, layout

**Chat pane**:
The pane that shows a session's transcript and composer.
_Avoid_: conversation view, chat window

**Companion pane**:
A pane of the workspace panel other than the chat pane: the repository pane, the Git Changes pane or the browser pane.
_Avoid_: side pane, sidecar; never use it for the Agents pane

**Agents pane**:
The column beside the chat pane with the Agents, Side and Tasks tabs, which shows a session's subagents and workflows, its side conversation and its task list.
_Avoid_: sidecar, companion, Agents menu, Agents/Workflows panel

**Composer**:
The input area of the chat pane where the user writes prompts, steers and follow-ups and stages attachments and commands.
_Avoid_: input box, prompt field

**Command chip**:
A Pi slash command staged in the composer as a separate token, so the text field holds only its arguments.
_Avoid_: command tag, slash text

**Step group**:
The collapsible block in the transcript that gathers a turn's intermediate steps (thinking, tool calls and intermediate text) and keeps the final answer outside it.
_Avoid_: accordion, steps block

### Remote access

**Remote access**:
Using PiFrame from another device through a tunnel to a separate daemon listener, turned on by the user and off by default.
_Avoid_: remote mode, cloud access

**Paired device**:
A device that has redeemed a one-time pairing link and holds its own credential, with either view mode or control mode.
_Avoid_: remote client, linked device

**View mode / control mode**:
The two permission levels of a paired device: view mode can watch sessions and stop the agent, control mode can also prompt it and change the workspace.
_Avoid_: read-only mode, admin mode

**UI request**:
A dialog that a Pi extension asks the user to answer (confirm, select, input or editor); one client claims it at a time and answers for all (ADR 0010).
_Avoid_: prompt (that is the user's message), popup

### Development

**Harness**:
The developer tool in `tools/harness` that runs an isolated desktop build, drives the real app and saves real screenshots.
_Avoid_: test runner, simulator

**Fake Pi**:
The scripted stand-in for Pi in `tools/fake-pi` that replays a scenario, so tests and the harness run without a real model.
_Avoid_: mock Pi, Pi stub

**Escape hatch**:
Any way code silences a check (a lint suppression or a type escape); the escape-hatch audit only lets their count go down.
_Avoid_: suppression (on its own), workaround

**Guardrail**:
A check, its configuration or an agent guard whose weakening needs the human-approved label on the pull request.
_Avoid_: rule, policy

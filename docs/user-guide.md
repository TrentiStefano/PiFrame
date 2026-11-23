# PiFrame user guide

This guide describes what the PiFrame app does, feature by feature. To install, update or remove PiFrame, see the [install guide](install.md); if something does not work, see the [troubleshooting guide](troubleshooting.md). Terms such as session, steer or side conversation are defined in the [glossary](../GLOSSARY.md).

---

## 1. Sessions

### Sessions sidebar

Each session card shows what its agent is doing. A spinner and a coloured border mean the agent is working, even after you switch to another session. The dot on the left is a notification dot: it stays dark until the agent writes something you have not seen, then lights up until you open that session. A repository row and the **Pinned** header light their dot too when one of their sessions has news. Unread sessions are remembered across restarts in `~/.piframe/unread_sessions.json`. The outlined cursor on a card appears only while you move through the list with the keyboard.

When sessions or repositories have equivalent names (ignoring case and spaces), PiFrame adds the parent folders needed to tell the paths apart. For example, two folders `v1/PiFrame` and `v2/PiFrame` are shown as **v1 / PiFrame** and **v2 / PiFrame**; if the parents match too, further ancestors are added. The distinction stays visible in the list, in pinned sessions, in Quick Launch, in the chat title, in the `/resume` picker and in notifications. Saved names and rename fields do not change; sessions in the same folder can still share a name.

Drag the divider on the right edge of the **Sessions** pane to make it wider or narrower. This works both in the sidebar on wide screens and in the panel opened with **Open sessions**. The width is saved with the layout in `~/.piframe/layout.json`, stays the same when you collapse and reopen the sidebar, and is clamped to the available space on small screens. In the browser the choice lasts for the current visit, like the other layout preferences.

### Welcome screen and new session

When no session is open, the welcome screen is a place to pick work back up.

- **Resume work**: on the left, the description, **New session** (primary button) and **Browse sessions**. On the right, up to 8 recent sessions grouped by repository, as selectable rows. With a physical keyboard, ↑/↓ move and Enter opens the session. On phones and tablets (without a physical keyboard) the "Ctrl / Cmd + K" hint does not appear. Below 960 px of width the sessions move below the buttons; below 640 px the title is smaller.
- **First launch**: on the first start, the title, description and buttons appear in sequence (300 ms each, staggered by 100 ms, with a slight rise). With **Reduce animations** only a fade appears. The flag is saved in `~/.piframe/app_first_run.json` (key `introPlayed`), separate from `first_run.json`, which is about installing Pi; later launches do not repeat the animation.
- **New session**: opens a 480 px dialog with the "Folder path…" field (prefilled with the active session's folder, if any), a button to pick a folder from the computer and up to 5 recent folders to select with a click. The path is checked 300 ms after the last edit:
  - "Folder not found": the path does not exist and **Create** stays disabled;
  - "Git repository detected · <branch>": the folder is a Git repository, and the branch is read from `HEAD` (on a detached HEAD only "Git repository detected" appears);
  - "Folder found": an existing folder that is not a Git repository.
  Enter creates the session when the path is valid, Esc closes the dialog. The welcome button stays still until you press **Create**.
- In the browser the path cannot be checked on the computer: the field accepts any non-empty path and shows the reminder about the local path. On the computer the check uses the app's file system: if the app and the daemon run on different machines, the result is about the app's machine.

### Long histories

In sessions with a very long history (thousands of messages or large tool logs):
1. **Light initial snapshot**: when a session opens, the daemon sends a recent window limited to the latest 100 messages, so loading is fast and memory use stays low.
2. **Load earlier messages**: at the top of the chat, the *Load earlier messages* button fetches further blocks of older messages, keeping the scroll position without visual jumps.
3. **Complete history**: the full history stays in the session file under `~/.pi/agent/sessions/` and can be browsed backward step by step, down to the very first message of the session.

---

## 2. Chat pane and composer

### Pi slash commands and command chips

Type `/` in the composer to see Pi's built-in commands as well as those provided by extensions, prompts and skills. `/login` and `/logout` show the provider picker and use the Pi authentication flow; key and token fields are masked. Credentials stay in Pi's store, and these prompts are available only in the local app, not from remote clients. Other Pi terminal commands that are not available over RPC show a notice and are not sent to the model.

A command is never plain text:
- Pick a command from the `/` menu with a click, or with the `↑`/`↓` arrows and `Enter` or `Tab`. The command becomes a separate **command chip** at the start of the composer, with its name, its source (`Pi`, `extension`, `prompt`, `skill`) and an entry animation.
- Only the arguments stay in the text field. The hint shows which arguments the command takes.
- If you type `/name` followed by a space, the command becomes a chip at once. If you send a hand-typed `/name`, the first `Enter` turns it into a chip and the second runs it.
- `Enter` runs the command: while it runs, the chip shows a progress indicator.
- Pi and extension commands (for example `/reload` or `/caveman full`) do not create chat messages. Prompts and skills become a normal user message instead.
- `Backspace` in an empty field, or the `×` on the chip, removes the command. Without arguments, `/name` goes back into the field as editable text.
- Text that contains a `/` without a chip (for example `why does /reload fail?`) is sent as a normal message.

### Send with Enter

In **Settings → Appearance → Composer** there is a **Send with Enter** option (off by default):
- **Off (default)**: `Ctrl+Enter` (or `Cmd+Enter` on macOS) sends the message or applies the steer; `Enter` inserts a new line in the composer.
- **On**: `Enter` (or the numeric keypad `Enter`) without modifiers sends the message (or applies the steer while the agent is answering); `Ctrl+Enter` / `Cmd+Enter` still sends; `Shift+Enter` inserts a new line.
- While an IME composition is active (for example CJK input), `Enter` confirms the text without sending, in both modes.
- The preference is saved locally in `~/.piframe/composer_settings.json`.

### Composer during a run

**Status row.** While Pi answers, a 28 px row appears above the input field with the indicator *The agent is answering…*, the elapsed time and the **Stop** button. The row appears and disappears without moving the message being scrolled. With reduced motion the indicator is a static icon.

**Keys during a run.**
- `Esc` stops the run.
- With **Send with Enter** on, `Enter` sends a steer (it redirects the agent without stopping it); `Shift+Enter` inserts a new line.
- With **Send with Enter** off, `Ctrl+Enter` (or `Cmd+Enter`) sends the steer; `Enter` inserts a new line.
- To send a message after the current run, use **Follow-up: queue** to queue it as a follow-up.

**Review button.** When Pi changes files, the composer shows **Review changes (n)** with the number of changed files. Pressing it opens the review of the session's changes; pressing it again closes it. Without changes the button is hidden; it appears as soon as Pi changes a file.

**Empty chat.** A session without messages shows the name of the working folder, the Git branch (if any) and three hints: `/` for commands, `@` to attach a file, `Ctrl/Cmd+K` for the command palette. The input field takes focus as soon as it appears, so you can type at once.

### Step groups

PiFrame shows the intermediate steps the agent takes during a turn (thinking blocks, tool calls and intermediate text) in a compact step group, and keeps the final answer prominent:

- **Step grouping modes**:
  - **Full**: an ultra-compact chat. All intermediate steps, thinking blocks and non-final answers of the agent are grouped into one collapsed, expandable block: the chat shows only the user prompt, an indicator with the number of steps and the time taken, and the agent's final answer. While running, only the title of the last active step is shown, with a loading indicator and a cross-fade between one step and the next.
  - **With thinking (default)**: groups turns that contain thinking blocks (both in history and while streaming).
  - **Always**: groups every turn that has at least one intermediate step (thinking, a tool call or intermediate text).
  - **Off**: no grouping; every message, tool call and thinking block appears on its own in the normal chat flow.
- **Auto-collapse (on by default)**:
  - When a turn ends or a session opens, the step group collapses, showing a short header with the number of tools used, the elapsed time and an excerpt of the thinking.
  - Clicking the header, or pressing Enter/Space when it has focus, expands or collapses the group with a smooth animation.
  - The grouping mode and auto-collapse preference are saved locally and remembered across sessions.
- **Compact step list**: an expanded group takes at most half the window height. If there are more steps, the list scrolls inside it (while running, it follows the last step if you are already at the bottom). At the bottom, **Show all steps (N)** expands the list to full height. When the group is collapsed (by hand or at the end of the turn) and opened again, the compact list comes back.
- **Turn state**: a turn that reaches its final answer shows *Completed N steps*, with a warning icon if a step failed. *Stopped with errors* appears only if the turn itself ended in an error; *Stopped after N steps* if the user stopped it. The final answer always stays outside the group.
- **Working header**: while a group is running, its header text has a slow shimmer and a three-dot progress indicator. With **Reduce animations** the shimmer stops and the text is drawn in the theme's primary text color.

---

## 3. Keyboard shortcuts and title bar

On macOS `Cmd` replaces `Ctrl` unless noted. Shell shortcuts (rows marked "Shell") apply when no text field, composer, editor or terminal handles them first.

| Shortcut | Action | Where |
|---|---|---|
| `Ctrl+N` / `Cmd+N` | New session (opens the folder picker) | Shell |
| `Ctrl+,` / `Cmd+,` | Open Settings | Shell |
| `Ctrl+B` / `Cmd+B` | Show or hide the sessions sidebar; in a narrow window, open or close the sessions drawer | Shell |
| `Ctrl+Tab` | Go back to the previously active session (if it still exists) | Shell |
| `F6` / `Shift+F6` | Move focus to the next or previous pane (title bar, sessions, repository, chat, companion pane) | Shell |
| `Ctrl+1` … `Ctrl+4` / `Cmd+1` … `Cmd+4` | Move focus to sessions, repository, chat (composer) and the companion pane | Shell |
| `Ctrl+K` / `Cmd+K` | Open the Command Palette | Shell |
| `Ctrl+Shift+B` / `Cmd+Shift+B` | Open or close the session's side conversation | Shell |
| `←` / `→` with focus on a divider | Move the divider by 20 px (sessions sidebar and dividers between panes); dividers take focus with `Tab` | Dividers |
| `Ctrl+F` / `Cmd+F` | Search in the file open in the repository editor | Editor (Repository pane) |
| `Ctrl+G` / `Cmd+G` | Open *Go to line* | Editor (Repository pane) |
| `Ctrl+S` / `Cmd+S` | Save the open file | Editor (Repository pane) |
| `Enter` / `Ctrl+Enter` / `Cmd+Enter` | Send the message; depends on **Send with Enter** (see above) | Composer |
| `Shift+Enter` | New line in the composer (with **Send with Enter** on) | Composer |
| `Tab` / `Enter` | Accept the selected slash command or mentioned file | Composer |
| `↑` / `↓` | Move through slash commands, mentioned files and suggestions | Composer, file picker, Command Palette, branch picker |
| `Enter` | Confirm in the Command Palette, the branch picker and session rename | Palette, branch picker, session rename |
| `Shift+F10` / Menu key | Open the context menu of the focused row (or the cursor row) in the sessions list, the Git list and the file tree | Sessions, Git, Repository |
| `F2` / `Enter` on the session title | Rename the session (like double-clicking the title) | Session header |
| `F2` on the selected session row | Rename the session under the list cursor (not for folders) | Sessions |
| `Enter` on a session or folder row | Open the session, or expand or collapse the folder | Sessions |
| `Enter` on an unsent message | Put its text and attachments back in the composer (like double-clicking) | Chat |
| `Esc` | Close the topmost layer, in this order: menu, dialog, drawer (sessions or context), diff in the pane, Review mode, Settings. It stops the agent only when no layer is open and the composer has focus during a run | Shell (uniform) |
| `Tab` / `Shift+Tab` | Focus order: title bar, sessions, repository, chat, composer, companion pane; top to bottom inside each pane | Shell |
| `←` / `→` | On the companion pane tabs (Files, Review Changes, Chat): select the previous or next tab; `Enter` or `Space` selects the focused tab | Companion pane |
| `Enter` / `Ctrl+Enter` / `Cmd+Enter` | Send in the side conversation (according to **Send with Enter**) | Side tab |
| `Ctrl+C`, `Ctrl+L`, `Ctrl+V` | Interrupt, clear the screen, paste in the terminal | Integrated terminal |
| Arrows, `Tab`, `Enter`, `Backspace` | Sent to the integrated terminal's shell | Integrated terminal |

**Conflicts.** The composer and text fields handle `Tab` and `Enter` before the shell, so `Ctrl+Tab` is not used while the slash command menu is open. The integrated terminal handles `Ctrl+C`, `Ctrl+L`, `Ctrl+V` and `Tab` first, so they stay with the terminal. `Ctrl+Shift+B` opens the side conversation, not the sessions sidebar, which stays on `Ctrl+B`.

### Title bar

The title bar has two groups separated by a thin vertical line:

- **View**: the menu to show or hide panes (from 900 px, with a session open) and the light/dark theme switch.
- **Workspace**: the **Session** button (model, context and branches of the session) and **Settings** (`Ctrl+,` / `Cmd+,`). From 1100 px the Session button shows its label; below that width it is an icon with a tooltip.

The daemon connection state sits on the left next to the brand mark. From 920 px it shows the dot and the label (*Local Pi* or *Not connected*); below 920 px only the dot remains, with a tooltip and a screen-reader description. A click opens **Settings → Diagnostics**.

### Pane animations and notifications

**Panes.** Showing, hiding or collapsing a pane (from the title bar **View** menu, or with the shortcut) animates its width. Text in the other columns does not rewrap during the animation: the layout is stable and the incoming pane fades into place. With **Reduce animations** (see [Reduced motion](#reduced-motion)) or the system preference on, the layout changes at once and the incoming pane only fades, without movement.

**Notifications (snackbars).**
- Success messages appear at the bottom right and close by themselves after 4 seconds. A click on the card closes them at once.
- Error messages stay visible until you close them with the ✕ (they are also announced to screen readers).
- With **Reduce animations** on, the notification does not slide: it fades in.

---

## 4. Agents pane: subagents, workflows and tasks

When the main agent starts subagents (`Agent`) or workflows (`SubagentWorkflow` from `@tintinweb/pi-subagents`), the **Agents** pane opens to the right of the chat pane. When the pane opens, also when you enter a session where it was already open or with agents at work, the Git Changes or browser pane is minimized; during a review it stays visible. When closed, the pane remains a vertical strip with the number of active agents; a click reopens it. The pane does not appear below 900 px of width.

The pane shows agents as a tree starting from the **Main session**:

- **Workflows**: name, state, duration, a bar with one segment per agent (green finished, colored working, red error) and the phases declared in `meta`. The workflow's child sessions, that is the subagents started while the workflow was active, hang below it. The script path is not shown. Expanded, it shows the description and the final result.
- **Agents**: task (for workflow agents, the first line of the prompt that they do not share with the others, for example `TASK: …`), type, model, cost (or `N/A`), duration and current activity: the tool in use with its main argument while it works, the last line of the answer when it has finished. Active branches have an animated ring and a spark running along the connector. Expanded, an agent shows its output; `Agent` subagents also accept a steer and an interrupt.

The state comes from the subagent package itself: PiFrame's extension in the Pi worker reports the subagents' live status, so the pane matches `/agents`. Activity and output are read from the child sessions' session files (`~/.pi/agent/sessions`). For a read-only session (for example, one open in a Pi terminal), the pane falls back to those files: a child session with no activity for 10 minutes is considered finished. This needs an up-to-date daemon: with an older daemon the pane shows only name and state.

**Stop** on an agent stops it through the subagent package's own stop, the same as `/agents`, and the pane says so if it could not. The main agent also has a `stop_subagent` tool, so you can ask it to stop a subagent. A running subagent whose session has not moved for 10 minutes shows *No activity for N min, it may be stuck*: usually a tool call that does not return; stop it, or steer it. PiFrame does not stop an idle Pi worker while one of its subagents is still running.

### Tasks tab

The agent's task list (todos) lives in the same pane, as a **Tasks** tab next to **Agents** and **Side**. The tab shows how many tasks are done (`Tasks (3/5)`). The pane's header lists its tabs and, on the right, one **>** button that hides the whole pane, whichever tab is showing; the tabs have no close buttons of their own. When the agent adds tasks, the pane opens on the Tasks tab, unless a side conversation is open there; once you hide the pane, new tasks no longer reopen it in that session. In the tab you can tick tasks, expand one to read its description, and add your own with **+**. When the pane is hidden, its strip reopens the last tab you used. An unsent message in the Side tab is kept when you hide the pane or switch tab.

Drag the thin line between the chat pane and the Agents pane to make the pane wider or narrower.

In the `/agents` menu, **Workflows (N)** opens this pane instead of the Pi terminal view, which is not available over RPC. In the Sessions sidebar, a session stays marked as running until its subagents or workflows finish.

---

## 5. Side conversations

A side conversation is a short-lived, read-only exchange about the current session, for questions you do not want in the main conversation ("Explain this function", "Review the tests", "Which constraints came up?"). The assistant answers from a snapshot of the session and can read the workspace files.

- **Opening it**: type `/btw [question]` or `/side [question]` in the composer (the composer handles them itself; they are never sent to the main agent and appear in the slash menu as *"Read-only side conversation"*), press `Ctrl+Shift+B` (`Cmd+Shift+B` on macOS), or pick *Side conversation* in the Command Palette (`Ctrl+K` / `Cmd+K`). Opening it splits the chat area, with the same animation rule as panes.
- **The Side tab**: side conversations live in the Side tab of the Agents pane, to the right of the chat pane, resizable by dragging (240–700 px). Every side conversation started in the session is kept and can be browsed through a row of pills, with an active, closed or error indicator, and deleted on request. A `+` button in the header starts a new one at any time.
- **Header and transcript**: the header has a `Side · read-only` badge, the active model chip, the count and the note *"Not part of the main conversation"*. A mini transcript shows the answers with the same rich content, thinking blocks and tool cards as the chat pane, and a mini composer takes follow-up questions, honoring **Send with Enter**.
- **Actions**: **Stop** interrupts the running answer and **Close** ends the side conversation; Esc or X closes the pane, asking for confirmation only if the mini composer holds a draft. **Insert into composer** on an answer appends its text to the main composer draft, only on an explicit click. When a side conversation ends (idle, parent session closed, error or closed by you), a notice says why.

What a side conversation can and cannot do:

- **It never changes the session.** The session file in `~/.pi/agent/sessions/` stays byte-for-byte identical, and no side conversation event reaches the session's journal. Its events are kept only in memory for the daemon's lifetime, so a client can reconnect; nothing is written to disk.
- **Read-only tools.** Its Pi worker runs with only `read`, `grep`, `find` and `ls`, without MCP servers, extensions or skills; tools that write or run commands (`bash`, `edit`, `write`) are not available.
- **Snapshot.** The session is copied to a temporary folder under `~/.piframe/runtime/side/`, readable only by you, capped at about 120,000 characters (the most recent exchanges are kept, with a notice when the cap is reached), and deleted when the side conversation closes or the daemon stops.
- **Limits.** One active side conversation per session (opening again returns the existing one), at most 4 at the same time on the computer, and an idle timeout after 10 minutes. It ends at once when its session closes.
- **Remote access**: opening and prompting need control mode; a device in view mode can still stop and close it.

---

## 6. Models and context limits

Open the **Session** button in the title bar → **Context size**, and choose a tier or **Custom**. For GPT-6 Luna the options are `Custom`, `272k (base tier)` and `1M (max / extended tier)`, unless the provider catalog declares different thresholds. Only Custom shows the maximum-window slider: **100,000–1,000,000 tokens**, in steps of **50,000**. The maximum is always reduced to the model's capacity and to the available grid; below 100k Custom is not available. Provider tiers keep their exact value, even when they are not multiples of 50k.

The context chip in the chat pane opens the same picker, with tiers and Custom kept in sync with the Session panel. If the catalog was not available yet at first launch, the click reloads it; an error is shown, not ignored. The sliders show the value while dragging and apply it on release.

The **Compaction margin (%)** slider goes from **0.5% to 25%**, in steps of **0.5%**. It is the share to keep free, not the share to fill:
- 200,000 tokens, default margin 2.5% → threshold 195,000 tokens.
- 1,000,000 tokens, margin 5% → threshold 950,000 tokens.

PiFrame applies the threshold to Pi, including between tool continuations; at the end of a turn it starts compaction if the threshold was reached. Automatic compaction that is disabled in Pi stays disabled. Wait for the turn to finish before changing these values. The context limit and margin are saved per session in `~/.piframe/context/`, restored when the session reopens and copied into duplicates. When you switch to a smaller model, the limit is reduced to its maximum.

The control uses an internal extension loaded only in PiFrame's Pi workers; it does not install `max-context` and does not change settings or credentials in `~/.pi/`. It needs Pi's `getSettings` extension API, verified with **Pi 1.4.0**. If your version does not support it, the app reports that the limit was not applied: update Pi and restart the Pi worker.

Like [max-context](https://github.com/indie-arch/max-context), it is a preventive check based on token use and estimates, not an accounting guarantee on cost. A single input, tool output or answer can exceed the margin before the next check, and the summary request uses tokens too. Use a wider margin for tools with large outputs. Very low limits may not fit the system prompt, the tools and the recent messages Pi keeps.

The GitHub Copilot picker checks the authenticated catalog and the organization's policies before applying any local `enabledModels` filters. It does not enable models or change GitHub policies. If the check fails, unverified Copilot models stay hidden and a notice appears; other providers stay available. A successful check is cached briefly: a policy change can take up to a minute to show.

---

## 7. Subagent settings (Settings → Agents)

The **Agents** tab in Settings shows and configures the subagents Pi can start:

- **Discovery**: it detects installed subagent packages (`pi-subagents` by nicobailon and `@tintinweb/pi-subagents`), built-in agents, user agents in `~/.pi/agent/agents/` and project agents in `.pi/agents/`. For each agent it works out the effective model and thinking level, where each comes from (`override`, `frontmatter`, `default` or `none`) and whether the model is available with your credentials.
- **Header and packages**: the detected packages with their version. If no package is installed, a banner explains how to install one from the CLI (`pi install pi-subagents`) or from the Packages tab. Configuration warnings from the daemon are highlighted. A note reminds you that changes apply globally to Pi (from the terminal too) and to new sessions and subagent runs.
- **Defaults for new sessions**: the default model for new sessions (the dropdown lists only available models, with a warning when credentials are missing) and the thinking level (limited to `off` if the model does not support reasoning). A *Reset* button removes the default.
- **Subagent defaults**: global subagent defaults (model and thinking for `pi-subagents`, or the fallback agent for `@tintinweb/pi-subagents`), with reset buttons and warnings for unavailable models.
- **Agent list**: every discovered agent, with a source badge (`builtin`, `user`, `project`, `package`), description, effective model with an origin badge, effective thinking and a context-limit picker (for example `272k`, `1.05M (full)`) when the model has more than one tier (otherwise `n/a` with the tooltip *Model has a single context tier*). Agents that cannot be edited (for example external CLI runners, project or tintinweb agents) are disabled, with a tooltip giving the reason. Every field has a *Reset* button that clears the override.
- **Save bar**: *Save changes* (enabled only when there are unsaved changes), *Cancel* to discard local changes, inline per-field validation errors and a success notice. Paired devices see the tab read-only, with a notice.

Where PiFrame writes your changes:

- With `pi-subagents` (nicobailon), Model and Thinking overrides go to `subagents.agentOverrides.<name>` in `~/.pi/agent/settings.json`. PiFrame takes a lock compatible with Pi's own, makes a `settings.json.piframe-backup` copy and writes atomically; a `settings.json` that is not valid JSON is never overwritten.
- `@tintinweb/pi-subagents` reads a subagent's model and thinking only from the agent file's frontmatter, so with tintinweb installed PiFrame rewrites the `model:` / `thinking:` line of user agents in `~/.pi/agent/agents/*.md`. Every other byte of the file stays as it was, a `<file>.piframe-backup` copy is made before each write, and the replaced line is recorded in `~/.piframe/subagent-frontmatter-originals.json`, so *Reset* puts the original line back (or removes the line if the field was absent). Package and project agents stay read-only. tintinweb has no per-agent context limit, so the Context control shows `n/a` with that reason.
- **Per-agent context limits**: the daemon generates a small extension in `~/.piframe/runtime/subagent-context-limit.mjs`, which Pi loads only for that subagent, so the main session and the installed packages are untouched. Before removing PiFrame, reset these limits (see [Uninstallation](install.md#6-uninstallation)).

---

## 8. Repository pane and file editor

Opening a file from the **Repository** pane opens the code editor, in a monospace font (Source Code Pro, 13/20 px) for every file type, Markdown included in source mode.

- **Line numbers**: the left column (44 px, in a muted tone) shows a number for every logical line, aligned also when lines wrap. The cursor line has a highlighted number and background.
- **Wrapping**: off for code, on for Markdown and plain text. The *wrap* button in the editor bar changes the choice for the open file.
- **Markdown**: the preview/source button switches between the formatted view and the source text.
- **Go to line**: `Ctrl+G` (`Cmd+G` on macOS) opens *Go to line*; type the number and press Enter.
- **Saving**: `Ctrl+S` (`Cmd+S` on macOS) saves the file. A file with unsaved changes shows a `●` next to its name and a filled *Save* button; with a clean file *Save* is a text button.
- **Unsaved changes**: closing the editor or switching session with unsaved changes asks *Save*, *Don't save* or *Cancel*.
- **Add selection to chat**: selecting text and opening the context menu (right-click) shows *Add to chat (file:L10–L24)*. The reference uses the real line range and the full file path in the composer.
- **Folder menu**: right-click a folder in the Repository pane for *New session here*, *Add folder to chat* (inserts `@folder` in the composer) and *Copy path*. File rows also show an *Add to chat* button on hover or focus.

The `Ctrl/Cmd+G` and `Ctrl/Cmd+S` shortcuts work when the cursor is in the editor.

---

## 9. Git Changes pane

- **Branch picker**: the current branch is a chip at the top of the Git Changes pane (with an icon and the commit SHA on a detached HEAD). Clicking it opens a picker with search, keyboard navigation (arrows, Enter, Esc), every local branch with its upstream state (↑n ↓m) and the date of its last commit.
- **Switching with uncommitted changes**: switching is refused while the workspace has changes, and a dialog shows how many files are changed or untracked. You can cancel, or stash the changes first: PiFrame stashes them as `piframe: before switching to <name> (<time>)` and puts them back if the switch fails. Switching is not available for read-only sessions or while the agent is working.
- **Fetch / Pull / Push / Sync**: at the bottom of the pane, four buttons run `git fetch --all --prune`, a fast-forward-only pull (a diverged history is refused, never merged silently), a push (a branch without upstream is published to `origin` with `--set-upstream`) and sync (pull, then push). Like every repository write, they are disabled for read-only sessions or while the agent works. PiFrame never opens credential prompts in a terminal, and Git errors appear in a notification.
- **Diff in the pane**: selecting a file replaces the list with its diff, and the chat stays visible above. The header shows "← Changes", the file name, the position (for example 2/5), previous and next file buttons, Stage or Unstage, Discard… and "Open in window", which shows the diff in a wider window. Keyboard: Enter opens the file under the cursor in the list; Alt+↓ and Alt+↑ move to the next or previous file, without animation; Esc or Alt+← go back to the list. Below 900 px the diff fills the whole pane.
- **Inline commit**: you write the commit message directly in the pane, above Fetch, Pull, Push and Sync. The subject is one line with a counter that references 72 characters; past that limit the counter switches to the warning color, but the commit is still allowed. The description is optional and opens with "Add description". The Commit button stays disabled while the subject is empty. Ctrl+Enter (Cmd+Enter on macOS) commits from the fields. In the compact layout (below 900 px) the Commit button takes the full width, below the four Fetch, Pull, Push and Sync buttons. After the commit, a notice shows the short hash of the new commit; if the commit fails, the error appears in the form and the message is kept.
- **Actions on Git rows**: stage, unstage and discard appear on hover or when the row has keyboard focus. Where there is no pointer (compact layout below 900 px, iOS, Android and the web on mobile devices) they are always visible.

---

## 10. Integrated terminal

The integrated terminal runs PowerShell, bash, zsh or WSL. Its processes use pipes, not a pseudo-console; PiFrame converts every lone line feed to a carriage return plus line feed before drawing the output, including stderr, so the output of tools such as `git branch` or `git log --oneline` stays aligned.

---

## 11. Settings

### Navigation

In windows at least 900 px wide, **Settings** shows a navigation column on the left with three groups: **General** (Appearance, Terminal, Updates), **Pi** (Pi CLI, Packages, Agents) and **System** (Daemon, Diagnostics, Remote access; privacy is under Diagnostics). In narrower windows the navigation becomes a scrollable row of tabs. The ↑/↓ arrows move the selection between sections, Esc closes Settings, and the header shows the state of the active session (for example *Running*) even while you are in Settings.

- **Appearance → Theme**: a single control with three choices, **System**, **Light** and **Dark**. With *System*, both the *Default dark theme* and *Default light theme* pickers appear; with *Light* or *Dark*, only the picker for that mode appears.
- **Diagnostics**: also holds the privacy text and the zero-telemetry note.
- **Terminal**: the list of native terminal apps is disabled until you choose *Native OS terminal*.
- **Daemon → Restart daemon**: the text under the button says that *running sessions will reconnect*. If an agent is running, PiFrame asks for confirmation before restarting.
- **Pi CLI**: the recommended command (`pi update`) is marked *Recommended*; every *Run* button is outlined. In wide windows the command output is in a column on the right; in narrow windows, starting a command scrolls the output into view.

### Packages: updating Pi packages

In **Settings → Packages**, the update buttons are enabled only after PiFrame has verified that a newer installable version exists. **Update all** is enabled when at least one package meets that condition, and it updates, one after another, only the packages with updates available, using the Pi package manager. Packages that are already current, pinned versions, incompatible updates and unverified versions are left out. After you confirm, progress is shown; the update, remove and pin buttons stay disabled until it finishes. If one package fails to update, PiFrame continues with the others and shows a summary with the errors of the failed packages. The list is checked when the page opens and reloaded at the end: the buttons are disabled again when no updates remain. Restart Pi to load the updated code. Project packages are not changed.

The summary separates updates that were actually installed from packages that were already current and from pinned versions. For npm packages the daemon compares the version on disk with the version the configured source expects: without a version it uses `latest`; with a range or a tag it keeps that constraint. A command that exits with code zero but leaves an older version is reported as an error. Update, remove and pin also re-check the update notice. On Windows the official standalone runtime in `%LOCALAPPDATA%\pi-node\current` is recognized too.

Before offering a newer npm version, PiFrame checks that it can be installed, including its required dependencies, with a dry run that runs no scripts. Versions not supported by the operating system do not trigger the update notice; the reason stays visible on the Packages page. The install, update and remove commands in the **Pi CLI** tab also re-check the list and the notice when they finish.

### Interface language

In **Settings → Appearance → Application Language** you can choose English or Italian. The choice applies to the whole interface: title bar, Sessions sidebar, Repository pane, chat pane and step groups, composer, Session panel and context picker, Git Changes pane, change review, integrated browser, terminal, Agents pane, side conversations, Settings, update and error messages, and desktop notifications. The daemon's own messages (for example the remote pairing page and "Read-only session.") are in English.

**Default language**: English.

- **New install** (no PiFrame settings file in `~/.piframe` yet): the app starts in English. Other files you keep in that folder do not count.
- **Existing install with no language choice** (a settings file saved by an earlier PiFrame, such as `theme_settings.json` or `window_state.json`, but no language picked): the app keeps Italian, the old default, so an update does not change your language.
- **Explicit choice**: the language you pick in Settings always wins.

The language is decided once, on the first launch of this version, and saved, so the rule above does not change later.

- **Desktop app**: the choice is saved in `~/.piframe/language_settings.json`.
- **Web and phone (remote access)**: the web client cannot read `~/.piframe`, so it saves the choice in the browser's `localStorage`. If you have never picked a language on that browser, the web client follows the browser's language when it is Italian or English, and starts in English for any other language.

### Technical stats

**Settings → Appearance → Technical stats** shows real-time system metrics in the title bar (off by default):
- **Off (default)**: the title bar shows no hardware metrics or frame counters, and PiFrame does not ask the daemon for them.
- **On**: a compact monospace box in the title bar shows, for example, `CPU 12.3% · RAM 48% · DISK 62% · GPU n/a · 60 FPS`. Hovering it shows a tooltip with exact RAM use (used / total and percentage), disk space on your main volume, GPU use with VRAM and the detection source, and the rendering frame rate.
- **Warning thresholds**: when a resource goes above 85% use, its percentage takes the active theme's warning color.
- **Unavailable or stale data (`n/a`)**: if a sensor or metric is not available, or no sample arrives from the daemon for more than 5 seconds (or the connection drops), the value is shown as `n/a`; PiFrame never makes up data.
- **FPS counter**: measured from the app's own rendering. When the app is idle, nothing is redrawn and the counter reports a low value or zero frames in the last second. The display refreshes at most once a second.
- **On the web**: the system metrics (CPU, RAM, disk, GPU) stay hidden; only the FPS segment is shown.
- **GPU support**: NVIDIA everywhere through `nvidia-smi`; Windows GPU engines through `typeperf` (only with an English system locale, otherwise `n/a`); AMD on Linux through `sysfs`; Apple Silicon through `ioreg`; anything else shows `n/a`.
- **Local only**: metrics are sampled on your computer and sent only from the daemon to the app over PCP (the PiFrame Protocol); nothing is stored or sent out. The preference is saved in `~/.piframe/nerd_stats_settings.json`.

### Reduced motion

**Settings → Appearance → Reduced motion → Reduce animations.**

- With the switch on, PiFrame stops moving elements: panes and rows appear with a fade, decorative loops (the composer's active ring, the dot of running sessions, the subagent animation) become static, and expand animations are short fades.
- The preference is saved in `~/.piframe/reduced_motion_settings.json` and applies to every session.
- The operating-system setting that asks to *reduce or remove animations* (macOS: Reduce motion; Windows: Animation effects off) is honored too. Either one turns reduced motion on.
- Circular working indicators become a static sync icon of the same size, so nothing spins on screen. Indeterminate progress bars in **Settings → Packages** and **Updates** become a full, still bar; a bar with a known percentage keeps showing it.

Normal motion: while the agent works, the composer ring runs around the border in a loop (3.6 s per lap) and stops when the work ends. Panes, rows and intermediate steps use short durations (120–240 ms).

### Startup animation

**Settings → Appearance → Startup animation.**

- The first time PiFrame opens, you see a startup animation of about 1.4 seconds, with audio. Later launches show the app at once with a short fade (620 ms).
- With the switch on, the animation with audio plays again on every launch.
- The preference is saved in `~/.piframe/startup_animation_settings.json`. The first-run flag is in `~/.piframe/app_first_run.json`.
- With **Reduce animations** on, the animation does not play.

---

## 12. Taskbar and dock indicators

While an agent is working in any session:
- **Windows**: the taskbar button shows an animated progress marquee while an agent is working, and a solid progress indicator when the agent finishes its answer while PiFrame is not focused.
- **macOS**: the dock tile shows a progress indicator and a `⋯` badge while the agent is working, and an unread dot (`•`) when an answer finishes while the app is in the background.
- **Linux and the window title**: the window title shows `● PiFrame` while an agent works and `• PiFrame` when an answer is unread.
- Focusing or opening PiFrame clears the unread indicator and the dock badge.

---

## 13. Release notes after an update

The first time you open PiFrame after an update, a dialog shows what changed in the new release:
- Only new features and bug fixes are listed, without internal changes; each entry shows the area it affects (for example `settings`, `chat`, `git`, `workspace`).
- The last version seen is saved in `~/.piframe/changelog_state.json`, so the dialog appears once per release and never on a new install.
- You can read the notes of the current release at any time in **Settings → Updates → Release notes**.

---

## 14. PiFrame on your phone (remote access)

With remote access turned on, the web app opened from a paired device works like this:

- **Startup checks**: before downloading the app, the browser checks the device credential. If the phone is no longer paired it shows "Pair the device again"; if the computer cannot be reached (PiFrame closed, Tailscale off on the phone) it shows a message and retries every 5 seconds. If the app does not start within 30 seconds, it offers *Reload*.
- **Pairing lasts**: the device cookie expires after 30 days and is renewed on each visit, so closing the browser does not unpair the phone.
- **Always the current version**: the daemon serves the most recently built copy of the web app and makes the browser revalidate it, so the phone never runs an old build after an update.
- **Speed**: web files are compressed and large messages are compressed on the WebSocket. On narrow screens the animated intro, the composer's glowing border and the sessions' animated working glow are off.
- **Taps match the screen**: the page does not scroll or zoom (no pinch or double-tap zoom), and any leftover iOS scroll or zoom after the keyboard closes is reset. The composer text is 16 px, so Safari does not zoom while you type, and the caret and selection land where they are drawn.
- **Compact composer**: below 600 px the model and effort pickers show only their icon (the tooltip is unchanged), the "expand" button does not appear, and the composer never grows past the space above the keyboard: a long message scrolls inside the field.
- **Step groups start collapsed** below 600 px, even while the agent works (a tap opens them), to leave room for the conversation.
- **Rounded corners on iPhone**: the bottom corners follow the display curve like native apps; with the keyboard open, or in a Safari tab with a toolbar, the normal corners come back.
- **Files and images from the phone**: the chosen file is uploaded to the computer (control mode needed, up to 50 MB) and the prompt carries its path there (`~/.piframe/blobs/<id>/<name>`), so the agent can read it. Sending waits until uploads finish; uploaded files are deleted after 14 days.
- **Tunnel restart**: if the tunnel does not start with the daemon (for example Tailscale is not ready yet), the daemon retries for up to 60 seconds.
- **Diagnostics**: opening the web app with `?pfdebug=1` shows a strip with the viewport and the coordinates of the last tap.

Pairing, view mode and control mode, and how the tunnel is protected are described in [docs/security.md](security.md).

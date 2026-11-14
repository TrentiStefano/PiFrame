# PiFrame — UI/UX, Visual, Interaction & Motion Design Audit

**Scope:** whole Flutter application (`apps/pi_frame`, theme package `packages/pi_frame_theme`), desktop first, with the remote mobile-web build as secondary evidence.
**Type:** audit only. No application code, theme, asset, dependency or other document was changed. This file is the only output.
**Evidence base:** 46 desktop captures and 56 mobile-web captures in `docs/ui-exploration/`, `DESIGN.md`, `docs/ui-exploration/NAVIGATION-MAP.md`, `README.md`, and Flutter source.

**Evidence labels used in this report**

| Label | Meaning |
|---|---|
| **[OBS]** | Directly observed in a real screenshot. The file name is cited. |
| **[CODE]** | Verified in source code. The path and line are cited. |
| **[RISK]** | Potential usability risk inferred from code or layout. Not observed at runtime. |
| **[OPP]** | Design improvement opportunity. Nothing is broken. |
| **[NV]** | Not verified. The evidence was not available or the state was not captured. |

Screenshot paths are relative to `docs/ui-exploration/`. Source paths are relative to `apps/pi_frame/lib/` unless they start with `packages/`.

---

## 1. Executive Summary

### Overall assessment

PiFrame has a sound, product-specific information architecture: **one session-bound workspace**, in which chat, repository files and Git Changes are co-visible Bento compartments, and Settings, dialogs and drawers sit around it. The DESIGN.md direction (Bento Triptych, PiFrame Dark/Light, quiet 1px borders, 6/10/14 radii) is visible and mostly coherent in the main workspace. The dark theme reads as calm and professional, and the token-driven colour system adapts to light mode without the black components that earlier reviews reported (`35-workspace-light-theme.png`).

The weaknesses are not in the direction. They are in **execution consistency and state communication**:

1. **Some core workflows have weak or missing feedback.** The P0 provider-error failure was confirmed in the running app by the maintainer and fixed in round 3 (§14.1): the live and replay reducers dropped an error on an empty assistant message when there was no prior assistant entry; this was not a `composer.dart:564–568` failure. `sendPrompt` also marks its optimistic entry failed before rethrowing. The Packages tab shows only a tiny spinner with no label **[OBS]**. Raw exception strings can reach the UI **[CODE]**. While the agent streams, an unfocused composer collapses into a status line that the user must hover to reveal (`40`); a focused composer stays open (`captures-r3/r5-02`) **[OBS]**.
2. **Layout defects in narrow companions.** The Web Browser companion overflows at its default width; Flutter's overflow stripe is visible in four captures **[OBS]**. The Git list truncates paths from the end, so the file names that tell rows apart are hidden **[OBS]**.
3. **The design system is documented but not enforced.** There is no spacing token. About 45 radius literals bypass the radius tokens. Hundreds of hard-coded font sizes (many 8–10.5px) override the type scale. No shared card, pane or chip primitive exists **[CODE]**.
4. **Keyboard and accessibility gaps.** Some custom controls built on `GestureDetector` cannot be reached by keyboard (companion tabs, chip remove). Escape behaviour is not consistent. Several hit targets are 20–28px. Round 2 captures show weak focus visibility; the shimmer, session-dot and subagent-pulse loops now respect reduced motion (§14.2).
5. **Motion remains partly ad hoc.** Round 3 added shared `FrameMotion` timings and curves, but hard-coded durations and curves remain. Pane, review-mode and diff state swaps still lack some transitions; dialog transitions differ by dialog **[CODE]**.

### Main strengths

- A clear spatial model that matches the product's job: session → chat + files + changes (`07-workspace-wide.png`, `43-git-staged-and-unstaged.png`).
- Semantic colour tokens with no feature-level hex literals **[CODE]**. Dark and light both render coherently.
- Compact, inspectable agent activity: a tool call is a single 28px row with duration and status (`36-tool-call-transcript.png`). This matches REF-012.
- A keyboard-first command palette and branch picker that share one visual grammar (`24-command-palette.png`, `28-branch-picker.png`).
- Explicit, guarded Git writes. A disabled-writes banner shows while Pi runs (`40-streaming-response.png`). The commit dialog names the repository, branch and files (`46-commit-dialog.png`).
- One-shot animations and press feedback respect `MediaQuery.disableAnimationsOf` **[CODE]**.

### Key improvement opportunities

1. Retain the new send-failure feedback; add clear result states for package loading, Git status and daemon errors.
2. Fix narrow-pane overflow and filename-first truncation in the Git, Browser and session lists.
3. Turn DESIGN.md §07 into code: spacing and type tokens plus 4–5 shared primitives.
4. Add keyboard parity (focusable tabs, a uniform Escape, focus visibility); activity loops now become static under reduced motion (§14.2).
5. Apply the new `FrameMotion` tokens to remaining pane, panel and diff transitions.

### Overall design quality

**Good foundation, inconsistent finish.** It is roughly a 3/5 against its own DESIGN.md contract. The workspace shell is close to the target. Settings, dialogs and secondary panels show visibly different conventions for headings, buttons, emphasis colour, save model and copy language.

---

## 2. Audit Scope & Methodology

### Documentation reviewed

| Document | Use |
|---|---|
| `DESIGN.md` (root, 1,165 lines) | Primary design reference: product truth, interaction contract, visual world (§05), tokens (§07), responsive rules (§10), D9 human-review feedback rounds 2, 4 and 9 |
| `docs/ui-exploration/NAVIGATION-MAP.md` | Route/shell model, breakpoints, dialog inventory, motion inventory, screenshot index and capture caveats |
| `README.md` | Product purpose and feature scope |
| `docs/ui-exploration/web/README.md` | Mobile capture provenance |
| `AGENTS.md` | Repository rules (real captures only, docs policy) |

The documentation was cross-checked against the code. See §7 for discrepancies.

### Screenshots inspected

- **Desktop:** the initial audit inspected `01`–`46` visually at 744×891, 1424×991, 1584×991 and 1784×1041. Round 2 then captured 31 additional real-app screenshots, `captures-r2/r2-01`–`r2-31`, including the 1280×720, 1440×900 and 1920×1080 viewports, hover and Tab-focus states, slash/@ menus, Packages after a wait, idle New-session and extension-confirm dialogs, crash-mid-stream, parallel tools, retry-then-success, and light-theme Git/Appearance. `11-settings-initial.png` is a documented duplicate of `12`.
- **Mobile web:** iPhone 12 full-screen `A`, `B`, `B1`, `B3`, `B4`, `B5`, `B6`, `B7`, `B8`, `B9`, `G` inspected; iPhone 18 `B-paired` inspected to confirm parity. Further mobile-web captures (iPhone viewport crops and remaining states) are out of scope by maintainer decision because Flutter's adaptive layout makes them low-value.
- **Classification:** all of the above are real Flutter renders (harness or Playwright WebKit), not mockups. Historical or fixture captures in `docs/design-evidence/` (bento-triptych fixtures, context-policy and question-preview fixtures) and `scratch/release_ui_screenshots/` were listed but **not** used as current-state evidence. Captures 08 and 11–41 show capture artefacts in Git Changes. File counts there are not designed data (NAVIGATION-MAP caveat).
- **Locale:** Italian. Copy findings refer to the Italian strings and their English equivalents in `data/language/`.

### Skills used

| Skill (requested name → resolved) | Status | How it was applied |
|---|---|---|
| `better-ui` → `.agents/skills/better-ui/SKILL.md` | Read and applied | Surface rules (concentric radius, borders for structure vs shadows for elevation), "same detail done two ways is a finding", press scale 0.96 / 150ms, high-frequency interactions ≤150ms, exits shorter than enters, theme-switch transition suppression, icon stroke and state consistency, severity model (HIGH = motion ignoring reduced motion or motion-only state). |
| `ui-ux-pro-max-skill` → `.agents/skills/ui-ux-pro-max/SKILL.md` (the installed name is `ui-ux-pro-max`) | Read and applied | Product-type lookup ("Developer Tool / IDE" → Dark Mode + Minimalism, Bento secondary; this agrees with DESIGN.md). UX-domain searches: *keyboard focus modal*, *loading empty state*, *reduced motion*, *status color only*. Flutter-stack theming rules (ThemeData, `Theme.of`, no hard-coded values). Pre-delivery checklist: contrast, colour-only meaning, disabled clarity, focus order, 4/8 spacing rhythm. The stack search for desktop focus returned **no Flutter match**, so the keyboard guidance here is the general UX-domain guidance. |
| `design-motion-principles` → `.agents/skills/design-motion-principles/` | Read and applied, **with documented deviations** | Audit workflow, audit checklist, anti-checklist, Emil Kowalski lens, accessibility reference. **Weighting:** productivity tool → **Emil primary** (restraint, <300ms, no animation for keyboard and high-frequency actions), **Jakub secondary** (production polish for panels and dialogs), **Jhey selective** (empty states, first run only). **Deviations:** (1) the workflow asks the user to confirm the weighting before the full audit. It was inferred instead, because DESIGN.md §05 already states the motion language ("keyboard actions immediate, short interruptible pane transitions"). (2) The workflow writes an HTML report to `motion-audits/`. This task allows only this Markdown file, so the motion findings and specifications are in §10. |

### Areas covered

The shell and title bar, Welcome, New-session dialog, Sessions rail and drawer, Chat transcript (user, assistant, tool, thinking, streaming), Composer and pickers, Context drawer, Repository tree, editor and terminal, Git Changes (staged, unstaged, diff, commit), Web Browser, Side conversation, Session tree, MCP manager, Command palette, Branch picker, Settings (all 10 tabs), Theme editor, Light theme, compact layout, and mobile web (unpaired, offline, workspace, drawer, settings, files, Git).

### Verification methodology

1. The documentation and skills were read.
2. The initial report's desktop screenshots and mobile sample were inspected visually. States of the same component were treated as sequences (for example 42→43→44→45→46 for Git, 37→38→39 for thinking, 40→41 for streaming). Round 2 captures are listed above; the lead's visual review is recorded in §15.
3. Four read-only sub-agents inspected the source in parallel: design system, navigation and interaction, desktop and accessibility, and motion. Their claims were consolidated here. The original composer attribution and reduced-motion findings are corrected against round 3 code in §14.1–§14.2. Other claims re-checked directly include the `(D9)`/`D16` IDs in user copy (`data/language/strings_settings.dart:99, 238, 784`) and the palette and branch picker use of `AnimationStyle.noAnimation`.
4. The initial audit did not run the app live. Round 2 added 31 real-app captures and round 3 added harness verification (§14.4); §15 contains the lead's visual review and live harness verification.

### Limitations and unverified areas

- Round 2 captures `captures-r2/r2-01`–`r2-31` cover the 1280×720, 1440×900 and 1920×1080 viewports; hover and Tab-focus states; slash/@ menus; Packages after ~10 seconds; idle New-session and extension-confirm dialogs; crash-mid-stream recovery; parallel tools; retry-then-success; and light-theme Git/Appearance. The focus sequence shows no crisp focus ring on any of 8 Tab steps; hover is a grey fill without a ring (§14.4).
- Slow-stream mid-stream (normal and reduced motion), the Git-discard confirmation and the delete-session confirmation were captured live by the lead in `captures-r3/r5-*` (§15). Both confirmations were cancelled; nothing was discarded or deleted.
- **[NV]** Review Changes is still not captured: it appears only when the agent has modified files, and no fake-pi scenario writes files.
- **[NV]** Text-scale behaviour was not exercised at runtime.
- Motion was assessed from code (durations and curves). No frame-by-frame playback was available.
- Further mobile-web captures (iPhone viewport crops and remaining states) are out of scope by maintainer decision because Flutter's adaptive layout makes them low-value.

---

## 3. Product & Design Understanding

**Purpose.** PiFrame is a Flutter desktop (Windows/macOS/Linux) and web GUI for Pi coding-agent sessions. A local daemon keeps Pi work alive when the window closes. Pi owns the session history. PiFrame adds session discovery and switching, live chat, editable repository files, IDE-style Git staging and committing, package and CLI management, and optional remote access.

**Target users.** Pi CLI users who work on a local developer workstation with keyboard and pointer. DESIGN.md asks for a *balance* between fast expert paths and discoverable controls for occasional users (Q-USER).

**Usage context.** Long-running agent work is followed intermittently, next to code and diffs. Sessions run long. The window is often at laptop size. The primary critical flow is **find/switch session → verify context → follow chat → review/stage changes** (DESIGN.md §03).

**Existing visual language.** Dark slate surfaces (`#161c27` background, `#1c2432` surface) with a steel-blue accent (`#5f9fc5`). There is a light counterpart. The bundled typefaces are Barlow Condensed (brand and headings), Schibsted Grotesk (UI) and Source Code Pro (code and paths). Bento compartments use 1px borders and modest rounding. The icons are Material.

**Design principles (DESIGN.md §04–05).** The session is the context boundary. Chat, code and changes are peers. Every write is accountable. Colour carries meaning, not decoration (REF-013 anti-reference). No glass, gradients or nested card stacks. Keyboard actions are immediate.

**Consistency with DESIGN.md.**

| DESIGN.md intent | Implementation status |
|---|---|
| Bento Triptych at ≥1440, chat + 1 companion 900–1439, switcher <900 | ✅ Matches (`app/app_shell.dart:731–830`) with one nuance (§7) |
| PiFrame Dark/Light as official themes | ✅ Present. Four extra legacy built-ins also ship (Catppuccin Mocha/Latte, Nord, Solar) (`packages/pi_frame_theme/lib/src/theme_repository.dart:18–143`) |
| 6/10/14px radii, 1px borders throughout | ⚠️ Partial. About 45 hard-coded radius literals, and isolated elevation/shadow outliers (§5) |
| 4px spacing scale, compact rows | ❌ No spacing tokens. The Git rows are 56px (`07`, `43`), contrary to the "compact session/Git rows" goal |
| Type roles 11/12/14/16/20/28 | ❌ Hundreds of literal sizes, many 8–10.5px (§5) |
| Status never by colour alone | ✅ Mostly (status badge has a label; Git rows have text). Exceptions in §9 |
| Intermediate transcript blocks borderless (D9 round 9) | ⚠️ The tool row is borderless (`36`), but the step group is still a bordered card (`37`–`39`) |
| Diff on file select | ⚠️ Implemented as a modal overlay (`44`), not in-pane |
| Motion: short, interruptible, reduced-motion aware, no decorative loops | ⚠️ Partial. Round 3 made shimmer and activity pulses static under reduced motion; other motion gaps remain (§10, §14.2) |

---

## 4. Global UI/UX Assessment

### G-1 Feedback for system status is uneven (P0/P1)
**[CODE][OBS]** The app shows run state well in the session header badge (`Completato`/`In esecuzione`) and blocks Git writes while Pi runs (`40`). Other states are silent or opaque:
- **Status: fixed in round 3 (§14.1); P0 was confirmed by the maintainer in the running app.** The root cause was in `session_reducer.dart` and `snapshot_reducer.dart`: an empty assistant provider error was dropped when there was no previous assistant entry. `applyTerminalStop` in `session_state.dart` now marks the user entry failed. The composer's non-streaming catch is not the user-visible failure: `sendPrompt` marks its optimistic entry failed on throw **[CODE]**.
- Packages: a centred ~6px spinner with no label, progress or timeout (`13-settings-packages.png`) **[OBS]** (fake-pi caveat).
- Raw exceptions are shown verbatim: `error.toString()` in the Git status and branch paths (`features/workspace/repository_workspace.dart:41, 246, 2087`), and package errors as `$source: $error` (`features/settings/settings_view.dart:233–240`) **[CODE]**. DESIGN.md round-2 feedback quotes one such leak: `Bad state: Unsupported command type: workspace.listFiles`.
- The daemon connection indicator disappears below 920px width (`app/app_shell.dart:473–485`) **[CODE]**.

*Impact:* the user cannot tell whether package data is coming or what to do after a raw exception. *Recommendation:* every async action ends in one of three visible states: success (quiet), recoverable error (inline message + Retry), or blocking error (dialog). Map exceptions to localized, actionable copy and keep the raw text in "Details".

### G-2 Same detail implemented several ways (P1)
The `better-ui` rule: *"The same detail done two ways within the project is a finding."*
- **Emphasis colour:** the Settings tab indicator is warning yellow (`12`–`21`). The accent everywhere else is steel blue.
- **Primary buttons:** the passive "Chiudi" is a filled primary in the session tree (`31`) and MCP dialog (`32`), but "Annulla/Crea" ordering and weights differ in the New-session dialog (`03`) and commit dialog (`46`).
- **Dialog headings:** Barlow display (`03`, `46`), Barlow small-caps-like (`22`), Schibsted bold with icon (`31`, `32`), or none (`44`, file path only).
- **Search inputs:** sessions search has one border (`07`). The repository search has an outer box plus an inner filled field, a double-border look (`05`, `07`). The palette search has a heavy focus outline (`24`).
- **Save model:** every Settings tab applies immediately except Agents, which has a sticky Annulla/Salva bar (`21`).
- **Status chips:** `CONNECTED`, `DISABILITATA` are full-width filled bars (`17`), `DISATTIVATO` is a small tag (`20`), `Completato` is a dot plus label (`05`).

### G-3 Language and internal jargon leak into the UI (P2)
**[OBS][CODE]** Internal design IDs appear in user copy: "Timeout Inattività Worker **(D9)**" (`14`), "politica di privacy **D16**" (`17`), "Privacy e Sicurezza **(D16)**" (`18`) — `data/language/strings_settings.dart:99, 238, 784`. Untranslated or English fragments appear in the Italian UI: `CONNECTED` (`17`), "No subagent package installed" (`21`), "untracked · unstaged" (`07`), "Side · read-only" (`30`), "Reasoning about problem…" (`38`). Bilingual parentheticals appear: "Duplica Ramo (Clone)", "Albero dei Rami (Tree)" (`29`). Raw enum casing appears: `LOW/MEDIUM/HIGH` (`34`, `29`). *Impact:* it lowers trust and readability and conflicts with DESIGN §08 ("never invent… preserve meaning under localization").

### G-4 Information density is unbalanced (P1)
Some areas are sparse and others overloaded. The Git rows are 56px tall for one path plus one truncated meta line (`07`, `43`). The user asked for less whitespace in D9 round 2. The session rail shows a single folder row and needs a click to expand it to reach sessions (`07`). The Welcome screen leaves about 70% of a 1424px window empty (`01`). Meanwhile the repository header packs 5 unlabeled icons (`05`) and the title bar packs 4 unlabeled icons, two of which look like settings (gear + sliders) (`05`).

### G-5 Icon-only controls without visible meaning (P2)
**[OBS]** Title bar: layout, theme, settings, workspace-drawer. Repository header: terminal, collapse-all, expand-all, refresh, hide. Composer: expand, attach, review, send. Editor: add-to-chat, wrap, search, close. Tooltips exist for most `IconButton`s (110 call sites) **[CODE]**, but tooltips are hover-only. *Recommendation:* keep icon-only for universal glyphs (refresh, close, search). Add short text labels or a grouped overflow menu for app-specific ones (layout, review, add-to-chat, workspace drawer). Never place two "settings" glyphs side by side.

### G-6 Empty states are inconsistent (P2)
The good ones are the session tree (`31`), MCP (`32`), Agents (`21`) and Side conversation (`30`): icon, title and explanation. They have **no actions**. The MCP manager tells the user to run a CLI command or edit a JSON file, and the Agents empty state points to the Packages tab, which in the capture was stuck loading. The chat empty state (`05`) is a blank pane. The collapsed Git groups make an entirely empty pane (`36`, `42`, `B9`). *Recommendation:* every empty state gets one next action (button) and, where relevant, a keyboard hint.

---

## 5. Design System Assessment

### 5.1 Colour
- **[CODE] Strength:** all feature colours resolve through `FrameTokens`/`ColorScheme`. No `Color(0x…)` or `Colors.*` literals were found in features. Light mode is coherent (`35`).
- **[CODE] Border contrast:** border `#2E3C53` on surface `#1C2432` ≈ **1.5:1**. Light `#D3DAE4` on white ≈ **1.4:1**. "Strong border" is also <3:1. This is acceptable for decorative compartment edges (a DESIGN choice). It fails WCAG 1.4.11 where the border is the **only** boundary of an input: the session search, file search, commit message field and composer. **P2.**
- **[OBS] Semantic misuse:** the Settings tab indicator is warning yellow (`12`). The MCP quick-command card has a danger-red border and a red "Gestisci" outline although nothing is wrong (`12`). The "Side · read-only" tag is danger-red (`30`). The Remote tab shows a missing *optional* binary as a full danger callout although the feature is off (`20`). This contradicts DESIGN REF-013/§05: "colour is strictly reserved for semantic indicators". **P2.**
- **[OBS]** The Context chip icon is danger-tinted at 1.2% usage (`05`), which reads as a warning when it is not one.
- **[CODE]** Six built-in themes ship, but DESIGN names two as normative. The `FileIcon` comment still says "Catppuccin" (`ui/code/file_icon.dart:3–4`). **P3.**

### 5.2 Typography
- **[CODE]** `ThemeData` defines 12/13/14/15px body roles and 28/32/56px condensed headings (`packages/pi_frame_theme/lib/src/theme_spec.dart:369–440`). Feature code overrides them heavily: hundreds of `fontSize:` literals, many 8–10.5px, some fractional. Examples: tool card 8–10.5px (`features/tool_timeline/tool_card.dart:436–494`), and Git row status **9px** (`features/workspace/repository_workspace.dart:2595–2599`). **P1**: the 8–9px metadata is below legible size on 100%-scaled Windows displays, and it ignores the DESIGN 11px floor.
- **[OBS]** Barlow Condensed appears in places where the role is not "brand/pane heading": the session title "Session 08:32:58" (`05`), dialog titles (`03`, `46`), and a tiny "Anteprima Componenti" (`22`). Settings section titles use Schibsted instead. The heading hierarchy therefore changes typeface by screen.
- **[OBS]** The editor renders Markdown **source** in the proportional UI font, with link styling and soft wrap (`27`), contrary to DESIGN ("Source Code Pro for code, file paths…"). **P1** for an editor.
- **[OBS] Web font fallback:** the offline "Riprova" button renders in a serif fallback (`web/iphone-12/full-screen/G-offline.png`). The unpaired and offline screens use the system font instead of Schibsted (`A-unpaired.png`). These screens are probably rendered before the fonts load. **P2.**

### 5.3 Spacing
- **[CODE]** There is no spacing token in `FrameTokens` (`packages/pi_frame_theme/lib/src/theme_tokens.dart:3–65`). The searches hit the 120-match cap. Off-scale values include 5/6/10/14/18px (`features/browser/web_browser_pane.dart:347–348, 488, 555`; `features/settings/remote_section.dart:546`; `features/composer/composer.dart:1800–1837`).
- **[OBS]** Settings column widths differ: the Remote cards are inset about 4px from the other tabs' column and use a stronger border (`20` vs `14`). Field heights differ inside one tab: language select ~56px, theme selects ~48px (`15`). **P2.**

### 5.4 Radius, borders, elevation
- **[CODE]** Tokens: 6/10/14/999. About 45 literal radii (1–12px) bypass them (`ui/code/code_block.dart:113`, `ui/code/diff_block.dart:153`, `features/settings/remote_section.dart:524, 541`). Elevation outliers: the startup banner is elevation 8, a sessions surface is elevation 4, and the attachment chips and side panel have `BoxShadow` (`features/updates/startup_update_banner.dart:46`, `features/sessions_sidebar/sessions_sidebar.dart:557`, `features/composer/attachment_chips.dart:227`, `features/side/side_panel.dart:151`). The side-panel shadow contradicts the flat grammar in DESIGN §05.
- **[OBS] Concentric radius (`better-ui`):** pane title bars (radius ~10) sit inside pane frames (~14) with about 8px inset. 10+8 = 18 ≠ 14, so the inner and outer corners do not look concentric (`05`, `07`). This is minor polish. **P3.**
- **[OBS]** The Theme editor header separator is a bright 2px near-white rule (`22`), unlike the token border used elsewhere.

### 5.5 Components
- **[CODE]** `lib/ui/` provides code/diff blocks, file icons, snackbar, press feedback, brand mark and shimmer. There is **no** shared pane header, card/section, chip/tag, status pill, toolbar icon button, empty state or list row. Each feature re-implements these, which is the root cause of G-2. **P1** (systemic).
- **[OBS] Buttons:** filled accent, outlined neutral, outlined accent and text styles mix without a hierarchy rule. In Pi CLI, two of eight "Esegui" buttons are filled and six are outlined, and nothing explains why (`12`). The disabled "Salva" in the editor is a large grey filled block that draws more attention than enabled controls (`27`).
- **[OBS] Selects:** Material dropdowns with 1-line and 2-line contents (`23` grouping select) in mixed heights.
- **[OBS] Toggles:** off-state switches use a thick white outline that is visually louder than the on state (`15`, `18`, `20`, `23`).

### 5.6 Iconography
- **[CODE]** Material Icons only (good: one library), but outlined, filled and rounded variants are mixed (`app/app_shell.dart:190, 593`; `ui/code/file_icon.dart:25`), and sizes run from 10 to 48px with a 20px global default. `better-ui`: one style per hierarchy level, stroke matched to text weight. **P3.**
- **[OBS]** Colourful file-type icons (yellow folders, blue docs, red YAML) bring the "colour sparks" asked for in REF-011. The `.gitignore` icon is a red branch glyph that reads as an error marker (`05`).

---

## 6. Screen-by-Screen Review

Each finding states **Priority · Scope · Complexity**. Complexity is S (hours), M (1–3 days) or L (>3 days).

---

### 6.1 Title bar / app chrome (global)

**Current state.** A 42px custom title bar: brand, "Pi locale" connection link, Comandi (palette), layout, theme, settings, workspace drawer, and caption buttons (`01`, `05`, `07`).

**Identified issues**
1. **[OBS]** Four adjacent unlabeled 16px icons. Gear (settings) and sliders (workspace/context drawer) are semantically ambiguous (`05`). *Impact:* the context drawer, which holds the model, thinking, context and compaction controls, is hard to find.
2. **[CODE]** The connection status is hidden below 920px (`app/app_shell.dart:473–485`). *Impact:* in compact windows the user loses daemon state.
3. **[OBS]** "Pi locale" is low-contrast muted text with a link icon. It is unclear whether it is a status or an action.

**Recommended improvements.** Group the right-side icons into *View* (layout, theme) and *Workspace* (context drawer, settings). Give the context drawer a labelled affordance ("Sessione") or move it into the session header next to the Context and Cost chips, which are the data it controls. Keep a compact connection dot with a tooltip and screen-reader label at all widths.

**Visual & layout.** Use a 28px icon-button target and 24px icons (16px glyph) with an 8px gap. Put a 1px divider between the groups. The connection indicator is an 8px dot + label ≥920px, dot only below that.

**Interaction.** Every icon has a tooltip with its shortcut. The connection dot opens Diagnostics.

**Motion.** None. Colour change on hover ≤120ms.

**Priority.** P2 · global · S.

---

### 6.2 Welcome (`01`, `02`, mobile `B-paired`)

**Current state.** Logo, the 72px Barlow headline "Nuova sessione.", a description, "Nuova sessione" (primary) and "Esplora sessioni" (secondary), and a Ctrl/Cmd+K hint. The content is left-aligned and vertically centred.

**Identified issues**
1. **[OBS]** The headline repeats the primary button label and names only one of the two jobs. The critical flow (DESIGN Q-FLOW) is *find/switch*, but the screen emphasises *create*.
2. **[OBS]** At 1424px, about 70% of the canvas is empty. Recent sessions are listed in NAVIGATION-MAP but were not visible in the captures because the home was isolated **[NV]**.
3. **[OBS]** The keyboard hint shows on touch devices (`web/iphone-18/full-screen/B-paired.png`).
4. **[OBS]** The logo has a rounded tile on mobile but not on desktop, so the brand treatment differs.

**Recommended improvements.** Make the welcome a *resume* surface. Use a short headline ("Riprendi il lavoro" or the product name), a list of the 5–8 most recent sessions grouped by repository with status, then the two actions. On wide windows, put a two-column layout: actions on the left, recent sessions on the right. Hide the keyboard hint when no hardware keyboard or pointer is detected.

**Visual & layout.** Limit the measure to 560px for the text column. Recent rows are 36px with 12px gaps between groups. Reduce the headline to 40–48px so the recent list is above the fold at 720px height.

**Interaction.** Arrow keys and Enter on the recent list. Ctrl+N creates, Ctrl+K opens the palette.

**Motion.** First-run only: stagger the title, description and actions 100ms apart (`better-ui` staged-entrance rule), each 300ms ease-out with 12px rise. With reduced motion, cross-fade.

**Priority.** P2 · first screen of every launch · M.

---

### 6.3 New-session dialog (`03`, `04`, mobile `B1`)

**Current state.** Title, a "Cartella di lavoro" field with placeholder `C:\Projects\my-project`, Scegli cartella, Annulla, Crea (disabled until a value is entered).

**Identified issues**
1. **[OBS]** The underlying welcome button already shows "Creazione…" (busy) while the dialog is still awaiting input (`03`, `04`). *Impact:* it suggests that creation started before confirmation (NAVIGATION-MAP flags this as a captured busy state).
2. **[OBS]** The placeholder looks like a real path in lighter grey, so it can be mistaken for a prefilled value.
3. **[OBS]** There is no recent-folders list and no validation hint (does the path exist? is it a Git repo?). Mobile adds a helpful note ("Nel browser inserisci il percorso…"), but desktop has none.
4. **[OBS]** "Scegli cartella" is a text button on the far left, separated from the field it fills.

**Recommended improvements.** Keep the welcome button idle until Crea is pressed. Use a neutral placeholder ("Percorso della cartella…"). Show up to 5 recent working directories as selectable rows under the field. Validate inline: "Cartella non trovata" or "Repository Git rilevato · main". Put the folder-picker icon button inside the field's suffix.

**Visual & layout.** Dialog width 480px, 24px padding, 16px between field and recent list, actions right-aligned: Annulla (text), Crea (filled).

**Interaction.** Autofocus the field. Enter creates when valid, Escape cancels. Validate on a 300ms debounce, and the error text is announced.

**Motion.** Standard dialog enter (see §10 token `dialog`). The recent list does not stagger.

**Priority.** P2 · every session creation · S–M.

---

### 6.4 Sessions rail / drawer (`07`, `10`, mobile `B6`)

**Current state.** Title, refresh, new, collapse; search; filter chips (Tutte / Gestite / Questo repo); repository rows (folder icon, status dot, name, path, + and ›); Impostazioni footer with search.

**Identified issues**
1. **[OBS]** Only the repository row is visible. Sessions need an extra expand, so the core *find/switch* path costs an extra click (`07`, `10`).
2. **[CODE]** The folder "new session" button is **20×20px** (`features/sessions_sidebar/sessions_sidebar.dart:749–758`). The + and › targets are tight on the row **[OBS]**.
3. **[OBS]** The filter chips are centred and separated from the list by a short underline that is not full width, which looks like a misalignment. The chips look like buttons, with no selected-state check.
4. **[OBS]** The footer has a second search icon next to Impostazioni, which duplicates the search field at the top.
5. **[OBS]** A session title defaults to a timestamp ("Session 08:32:58") in the header (`05`). When several sessions share a repository, timestamps are hard to tell apart **[RISK]**.
6. **[CODE]** Working-session pulse loop runs every 1.4s in normal motion (`sessions_sidebar.dart:1098–1118`). **Status: fixed in round 3 (§14.2); it is static under reduced motion.**

**Recommended improvements.** Expand the active repository by default, and auto-expand matches when searching. Show session rows (title, relative time, status) at 32px. Make the filter a left-aligned segmented control with a full-width divider. Remove the duplicate footer search. Raise hit targets to ≥28px. Use the first user prompt as the provisional title (DESIGN Q-COLD-TITLE allows a provisional title).

**Visual & layout.** Repository row 32px, session row 32px indented 20px, group gap 8px, row padding 8/12px. Status uses a dot plus a text tooltip; the running state shows a static ring rather than a pulse under reduced motion.

**Interaction.** Arrow-key tree navigation (←/→ collapse/expand, Enter opens). Type-to-filter when the rail has focus. Context menu: rename, delete, new session here.

**Motion.** Tree expand/collapse uses a 160ms size + fade (`panel` token). There is no animation for keyboard-initiated expand (Emil).

**Priority.** P1 (critical flow) · high frequency · M.

---

### 6.5 Session header (chat pane) (`05`–`09`, `36`–`45`)

**Current state.** Barlow title + rename pencil, cwd path in mono, Context chip ("Contesto · 1.2% · —/—"), Cost chip ("Costo · $0.0010 ▾"), status pill.

**Identified issues**
1. **[OBS]** "—/—" in the Context chip is cryptic, and the info icon only explains on hover.
2. **[OBS]** The context icon is danger-red at 1.2%, which reads as a warning.
3. **[OBS]** The header is a bordered card nested inside the bordered chat pane: a nested-card stack, which DESIGN §05 rejects.
4. **[OBS]** The model, thinking and context window appear in the composer, and context usage appears in the header and again in the drawer (`29`). The metadata is split over three places (DESIGN §04: "avoid duplicating metadata across panes").

**Recommended improvements.** Turn the header into a flat pane title bar (no inner card): title · cwd · status on one line, with metric chips right-aligned. Show context as "12k / 128k (1.2%)" or "— / 128k" when unknown. Use neutral colour below a threshold and warning/danger only near the compaction threshold. Clicking a metric opens the context drawer, so all session controls have one home.

**Visual & layout.** Height 48px. Title 16px semibold (Schibsted, or Barlow 18px if brand headings are kept), path 12px mono muted, chips 24px tall.

**Interaction.** Double-click the title to rename. Escape cancels a rename (already implemented, `features/transcript/transcript_view.dart:2137–2145`).

**Motion.** Status pill colour cross-fade 120ms (existing). No pulse.

**Priority.** P2 · every session · S.

---

### 6.6 Chat transcript (`06`, `36`–`41`, mobile `B5`)

**Current state.** The user message is a filled accent-tinted card with "Tu" and "Riparti da qui". The assistant message is an outlined card with "Assistente" and copy. Tool calls are compact rows. Thinking is grouped in a bordered "Completato 1 passaggio" card. Streaming text is in a borderless-header card with a timer chip. A scroll-to-bottom FAB appears.

**Identified issues**
1. **[OBS]** The step group is still a bordered card (`37`–`39`), while the tool row is borderless (`36`). D9 round 9 asked for all intermediate blocks to be borderless.
2. **[OBS]** Streaming changes the block's structure. The streaming block has no role header and shows the timer *below* the block (`40`). On completion the "Assistente" header appears and the timer moves into it (`41`). *Impact:* layout shift at the end of every response.
3. **[OBS]** Both roles are full-width cards with headers. A large share of each turn's vertical space is chrome (the header row is about 40px for a one-line reply, `06`).
4. **[OBS]** "Riparti da qui" (fork from here) is always visible on every user message. It is a consequential action at the same weight as metadata.
5. **[CODE]** Tool-card and step-group expansion originally snapped while the thinking block animated (`tool_card.dart:542–550`, `steps_group.dart:889–894`, `thinking_block.dart:157–163`). **Status: partially fixed in round 3 (§14.2): tool cards and steps now use `FrameExpandable`; see §14.2 for the remaining motion items.**
6. **[OBS]** Empty chat (`05`) is a blank pane with no suggestions or hint.

**Recommended improvements.** Keep the user turn as a tinted block. Render the assistant turn as plain text on the pane surface (no border), with role and actions in a hover/focus-revealed 24px meta line that is reserved in layout from the first token. Then streaming and settled states share one geometry. Make the step group a borderless summary row like the tool row. Move "Riparti da qui" into a hover/focus action group with copy. Add an empty-chat state: cwd and branch summary plus 2–3 example prompts or slash-command hints.

**Visual & layout.** Turn gap 16px, intra-turn gap 8px. Max reading measure about 760px centred inside wide chat panes. Activity rows 28px (as REF-012).

**Interaction.** Keyboard: J/K or ↑/↓ moves between turns when the transcript is focused (optional). Copy and fork are reachable by Tab.

**Motion.** Expanding a tool or step group: height + opacity, 160ms, `enterCurve`. Collapse is 120ms. Under reduced motion, cross-fade only. Do not animate streamed tokens (DESIGN: "no streaming theatrics").

**Priority.** P1 for item 2 (layout shift on every response) · P2 for the others · M.

---

### 6.7 Composer & pickers (`05`, `33`, `34`, `40`, mobile `B3`/`B4`)

**Current state.** A unified card: multiline field; model, thinking and context chips; expand, attach, review and send buttons. Pickers are small anchored popovers. While streaming, the composer collapses to a line: "L'agente sta rispondendo… Passa il mouse o clicca per scriv…" + Interrompi + expand.

**Identified issues**
1. **[CODE]** The P0 failure was confirmed by the maintainer in the running app and fixed in round 3 (§14.1). The root cause was not `composer.dart:564–568`: live and snapshot reducers dropped a provider error on an empty assistant message when no previous assistant entry existed. `applyTerminalStop` now marks the user entry failed; `sendPrompt` also marks its optimistic entry failed when it throws. **Status: fixed in round 3 (§14.1).**
2. **[OBS]** The collapsed streaming composer hides input behind a hover/click instruction, and the instruction itself is truncated (`40`). Steering and follow-up are core Pi interactions. The hover-only affordance fails for keyboard users and touch.
3. **[OBS]** Thinking levels are raw uppercase enums (OFF/LOW/MEDIUM/HIGH), each with the same bolt icon (`34`).
4. **[OBS]** The review icon (chat-with-pencil glyph) is ambiguous. Expand (diagonal arrows) is also unlabeled.
5. **[CODE]** Compact width shows the model and thinking chips as icons without labels (`composer.dart:2626–2643, 2720–2738`; mobile `B3`), so the current model cannot be seen.
6. **[CODE]** ShimmerBorder runs a 3.6s activity animation while the composer is active (`ui/shimmer_border.dart:51–58`). **Status: fixed in round 3 (§14.2): it is static under reduced motion.**

**Recommended improvements.** The original recommendation was to surface every send failure inline above the field ("Invio non riuscito: <reason> · Riprova") and keep the draft; round 3 instead fixed the transcript's failed-entry state with an error and retry (§14.1). Keep the field visible while streaming: show a slim status line *above* the field (spinner, elapsed time, Interrompi) and make Enter steer and Alt+Enter follow up, with the hint shown in the placeholder. Localize the thinking levels ("Spento / Basso / Medio / Alto") with a 4-step bar icon showing the level. Label review as "Rivedi modifiche (n)". On compact width, truncate the model name instead of hiding it.

**Visual & layout.** Composer min height 96px, padding 12px. Chips 28px tall, 8px gap. Send button 32px. The streaming status line is 28px and does not collapse the field.

**Interaction.** Esc interrupts only when the composer has focus and Pi is running (already the case). Shortcuts are shown in tooltips. The thinking level can be changed with Ctrl+T (opportunity).

**Motion.** The status line enters with 150ms fade + 4px rise. **Status (round 3, §14.2):** the composer height tween is now 240ms with `FrameMotion.enterCurve`; the shimmer/activity animation is static under reduced motion.

**Priority.** P0 (item 1; confirmed and fixed in round 3, §14.1) · P1 (items 2, 6) · P2 (others) · M.

---

### 6.8 Context / model drawer — "Area di lavoro" (`29`, `31`)

**Current state.** A right end-drawer with the Model, Thinking and Context selects, a compaction-margin slider with explanation, a usage bar, Compatta contesto, Duplica Ramo (Clone), and Albero dei Rami (Tree).

**Identified issues**
1. **[OBS]** "Dati non disponibili" is shown next to "1.2 %" for context usage, which is contradictory.
2. **[OBS]** Title hierarchy: "Area di lavoro" (Barlow 28) above "Sessione" (Barlow 24 on a tinted band) produces two competing headings for one panel.
3. **[OBS]** Three full-width outlined buttons have equal weight. Compaction (consequential, affects context) looks the same as opening a dialog.
4. **[OBS]** Opening the session tree leaves the drawer open underneath the dialog (`31`), which stacks two overlays.
5. **[OBS]** The tree dialog shows a raw session ID (`s_01M77AS47…`).

**Recommended improvements.** One heading ("Sessione · <title>"). Group into *Modello*, *Contesto* and *Rami* sections with 24px section gaps. Make Compatta contesto a primary action within *Contesto*, with the expected effect ("~X token liberati" when known). Close the drawer when a dialog launched from it opens, or present the tree inside the drawer. Show the session title, not the ID, with the ID in a copyable detail row.

**Priority.** P2 · occasional · S–M.

---

### 6.9 Repository pane: tree, editor, terminal (`05`, `26`, `27`, mobile `B8`)

**Current state.** Header (REPOSITORY + terminal, collapse-all, expand-all, refresh, hide), cwd path, file search, tree with colourful icons and an always-visible add-to-chat icon per file. The editor is a header with back, filename, Salva, add-to-chat, wrap, search and close. The integrated terminal has tabs.

**Identified issues**
1. **[OBS]** The editor shows **source** text in the proportional UI font, with clickable link styling, soft wrap and no line numbers (`27`). *Impact:* it is unreliable for code editing and line referencing. The user asked for line-precise "Add to chat" (D9 round 2). **P1.**
2. **[OBS]** The disabled "Salva" is a dominant grey block. There is no dirty indicator on the filename (a dot or "●") when the buffer changes **[NV for dirty state]**.
3. **[OBS]** The add-to-chat icon repeats on every file row, which adds visual noise (`05`).
4. **[OBS]** The search field has a double border (outer container plus inner filled field).
5. **[CODE]** Tree rows are 28px fixed height (`repository_workspace.dart:3546–3549`), which risks clipping with text scaling.
6. **[CODE]** The context menu exists for files (add to chat, copy path) but not for folders (`repository_workspace.dart:3490–3534`).
7. **[OBS]** The terminal is good: mono font, tabs, chassis background. Its header icons (new, stop, clear, external, collapse, close) are unlabeled.

**Recommended improvements.** Use Source Code Pro with a line-number gutter, no link decoration in source mode, wrap off by default for code (toggle kept), current-line highlight, and a selection → right-click → "Aggiungi alla chat (file:L10–L24)" action. Make Salva an enabled text/filled button only when dirty, and add "●" to the filename tab. Reveal add-to-chat on row hover or focus, and keep it in the context menu. Use a single-border search field. Add a folder context menu (new session here, copy path, add folder to chat).

**Visual & layout.** Editor font 13px / 20px line height, gutter 44px muted. Tree row 26–28px with min-height (not fixed), indent 16px.

**Interaction.** Ctrl+S saves, Ctrl+F searches (exists), Ctrl+G goes to line (opportunity). Unsaved-changes guard on close and on session switch (DESIGN §11).

**Motion.** No animation for tree expand (high frequency) or ≤120ms.

**Priority.** P1 (editor typography and line numbers) · P2/P3 (others) · M–L.

---

### 6.10 Git Changes (`07`, `08`, `40`, `42`–`46`, mobile `B9`)

**Current state.** Header (GIT CHANGES, Browser tab, globe, refresh, hide), repo path, branch chip, summary "2 file +2 −2", collapsible STAGED and CHANGES groups with counts and group actions, file rows (icon, path, meta line "modified · staged · Origine non determin…", stage/unstage, discard), Fetch/Pull/Push/Sync row, Commit (n) button. The diff opens as a modal overlay. The commit dialog lists repo, branch and files with a one-line message field.

**Identified issues**
1. **[OBS]** The path is end-truncated, so in deep folders every row reads "docs/ui-exploration/…" and the distinguishing file name is cut (`07`, `08`). **P1**: core review flow.
2. **[OBS]** Rows are 56px with a redundant meta line. "staged" under a STAGED heading and "unstaged" under CHANGES repeat the group. "Origine non determinata" is truncated on every row. The status text is 9px **[CODE]** (`repository_workspace.dart:2595–2599`). The user requested less whitespace in D9 round 2.
3. **[OBS]** Both groups are collapsed by default in several states (`36`, `42`, `B9`), which leaves a large empty pane with no hint.
4. **[OBS]** The unstage glyph (⊖) and stage glyph (+) are small and close to discard (↶). A mis-click on discard is guarded by a confirmation **[CODE]** (`repository_workspace.dart:2386–2433`) but cannot be undone.
5. **[OBS]** The diff is a large modal with a fixed height and no file navigation (`44`). It hides chat and the file list. The ~60% empty lower area is wasted for small diffs. There are no stage or discard actions in the diff.
6. **[OBS]** Commit dialog: a single-line message field, no subject/body split and no character guidance. The "Commit" button appears enabled while the message is empty (`46`) **[NV whether pressing is blocked]**.
7. **[OBS]** The "Scritture disabilitate…" banner inserts above the list and pushes it down by about 40px when Pi starts (`40`), causing a layout shift.
8. **[CODE]** No right-click menu on Git rows (`repository_workspace.dart:2568–2637`).
9. **[OBS]** Mobile: Commit floats bottom-right, misaligned with the four equal Fetch/Pull/Push/Sync buttons (`B9`).

**Recommended improvements.** Use filename-first rows: **name** in primary text, parent directory in muted text after it, and middle-truncation of the directory. Use a single-line 28px row with a status letter badge (M/A/D/U) plus colour, and drop the redundant meta. Show provenance (agent/manual) as an icon with tooltip only when known. Expand CHANGES by default when non-empty. Open the diff **in the companion pane** (or the editor slot), replacing the list with a back/next file header and stage/discard buttons, so the chat stays visible. Use a two-field commit form (subject 72-char guide, optional body). Disable Commit until a subject exists. Reserve the banner space, or render the banner as a compact inline state on the action bar. Add a context menu: Apri diff, Stage/Unstage, Scarta…, Copia percorso, Aggiungi alla chat.

**Visual & layout.** Group header 28px, row 28px, status badge 16px mono 11px. Actions are revealed on hover/focus but stay keyboard-reachable. The action bar is a 36px row; Commit is the primary and spans the full width in the compact layout.

**Interaction.** ↑/↓ moves through files, Enter opens the diff, Space stages or unstages, Delete discards with confirmation. In diff view, Alt+↓/↑ moves to the next/previous file.

**Motion.** Stage/unstage: the row moves between groups with a 160ms opacity + 4px translate (FLIP-style). Do not animate under reduced motion. Diff open in pane: list → diff slides 8px + fade, 180ms.

**Priority.** P1 (items 1, 2, 5) · P2 (3, 6, 7) · P3 (8, 9) · M–L.

---

### 6.11 Web Browser companion (`25`, `26`, `27`, `30`)

**Current state.** Companion tabs (Git Changes | Web Browser), a browser tab strip ("Home"), a nav row (back, forward, reload, home, address, star, extensions menu), quick-link chips, and a centred home page with Google search and bookmark chips.

**Identified issues**
1. **[OBS]** A Flutter **RenderFlex overflow stripe** ("RIGHT OVERFLOWED BY…") is visible in the top-right of the companion header in four captures (`25`, `26`, `27`, `30`). In release builds the controls are clipped silently instead. **P1.**
2. **[OBS]** At about 290px width the address field truncates to "Cerca o ins…" and the quick-link row clips ("GitH"). There are three rows of controls before any content.
3. **[OBS]** The quick links appear twice (the chip row under the nav and the "Segnalibri veloci" grid).

**Recommended improvements.** Use a one-row toolbar with an overflow menu below about 360px. Put the tab strip in the companion title bar, which D9 round 9 asks for. Remove the duplicate quick-link row. Give the companion a minimum width (≥320px), or collapse it to a tab when it would be narrower.

**Priority.** P1 · when the browser is used · S–M.

---

### 6.12 Side conversation (`30`)

**Current state.** A read-only side thread opened with Ctrl+Shift+B. It is a panel overlaid on the right half of the chat pane, with a red "Side · read-only" tag, an empty state and its own input.

**Identified issues**
1. **[OBS]** The panel **covers** the chat instead of splitting it. The session title, the user message and the assistant reply are clipped mid-word ("Session 08:32:5", "Describ"). The panel has a drop shadow **[CODE]** (`features/side/side_panel.dart:151`).
2. **[OBS]** The danger-red tag signals an error. Read-only is a neutral state.
3. **[OBS]** Its input (pill field + circular send button) differs from the main composer.
4. **[CODE]** Closing requires a confirmation dialog (`side_panel.dart:289–300`). Escape has no consistent close behaviour.

**Recommended improvements.** Make it a true split inside the chat pane: the main chat narrows and the side panel takes 40%, with a resizable divider. It could also be a fourth Bento compartment at ≥1440px. Use a neutral or info tag ("Laterale · sola lettura"). Reuse the composer component in compact mode. Confirm only if a side draft exists.

**Motion.** Enter: width/translate from the right edge, 240ms `panelCurve`. Exit: 180ms. Under reduced motion, cross-fade 150ms.

**Priority.** P1 · occasional but breaks the main view · M.

---

### 6.13 Command palette (`24`) and Branch picker (`28`)

**Current state.** Centred 540px overlays with a search field, an ESC hint and a list. The palette has 6–8 commands. The branch picker shows remote and ahead/behind info and a "Ramo corrente" tag.

**Identified issues**
1. **[OBS]** Shortcuts are written into command titles ("Conversazione laterale (Ctrl+Shift+B)", "Interrompi agente (Esc)") instead of right-aligned key hints. The macOS handler accepts Cmd while the label says Ctrl **[CODE]** (`data/language/strings_shell.dart:301–303, 522–525`; `app/app_shell.dart:360–379`).
2. **[CODE]** Coverage is limited: Review Changes, pane visibility, session switching, Git actions, terminal and theme are missing (`features/command_palette/command_palette.dart:97–190`). For a keyboard-first workbench, the palette should reach every major action.
3. **[OBS]** Irrelevant commands are shown in context. "Interrompi agente" appears on the Settings screen with no run active (`24`).
4. **[OBS]** The branch picker list has a fixed height, leaving empty space below 6 items (`28`). Long branch names truncate and push the remote column out of alignment.
5. **[OBS]** The search input focus outline is heavy (2px accent) relative to the rest of the system.

**Recommended improvements.** Use key-cap hints on the right, platform-aware (⌘ on macOS). Group commands (Sessione, Vista, Git, Impostazioni) and add the missing actions, including "Vai a sessione…" with fuzzy search. Hide or disable unavailable commands with a reason. Fit the list height to its content with a maximum of 60vh. Use a fixed column grid for branch, remote and ahead/behind.

**Motion.** Keep it instant (keyboard-initiated, Emil). The current `AnimationStyle.noAnimation` is correct. Apply the same rule to every keyboard-launched overlay.

**Priority.** P2 · high-frequency for experts · M.

---

### 6.14 Session tree dialog (`31`) and MCP manager (`32`)

**Issues.** **[OBS]** Large empty bodies for empty states (the MCP dialog is about 560px tall with one message). The passive "Chiudi" is a filled primary. "Ricarica" in the tree footer and refresh in the MCP header are placed inconsistently. The MCP header icon uses a danger-red tile. The session tree shows a raw ID. **[CODE]** The tree close icon has no tooltip (`features/session_tree/session_tree_dialog.dart:108`).

**Recommendations.** Fit dialog height to content (min 240px). Use a text-button "Chiudi" or the header ✕ only. Put refresh in the header in both dialogs. Give the empty states an action ("Aggiungi server MCP…" opening a form or the config file). Use a neutral icon tile.

**Priority.** P3 · rare · S.

---

### 6.15 Settings shell (`12`–`23`, mobile `B7`)

**Current state.** A full-screen view replacing the workspace. A header card with back, the Barlow title "Impostazioni PiFrame", and 10 uppercase tabs with a yellow indicator. Content is a centred ~912px column.

**Identified issues**
1. **[OBS]** The yellow indicator conflicts with the accent and status colour semantics.
2. **[OBS]** Ten uppercase tabs in one row. On mobile only 4 are visible, with no scroll affordance (`B7`). The tab set mixes app preferences (Aspetto, Terminale), system status (Daemon, Diagnostica) and product features (Pi CLI, Pacchetti, Agenti).
3. **[CODE]** There is no Escape handler to leave Settings (`features/settings/settings_view.dart:745–754`). Only the back arrow works.
4. **[OBS]** Settings replaces the whole workspace, so a running agent is not visible while the user changes settings.
5. **[CODE]** Tab content swaps directly. The `TabBarView` default page swipe is disabled.

**Recommended improvements.** Use a left vertical nav (desktop ≥900px) with three groups: *Generale* (Aspetto, Terminale, Aggiornamenti, Privacy), *Pi* (Pi CLI, Pacchetti, Agenti), *Sistema* (Daemon, Diagnostica, Accesso remoto). Use sentence-case labels and an accent-blue selection bar. Escape and Ctrl+, close or open. Optionally show Settings as a large modal sheet over the workspace so run status stays visible.

**Visual & layout.** Nav 220px, content max 760px, section gap 32px, card padding 16px.

**Motion.** Content switch: 120ms cross-fade, or none (frequent, often keyboard-driven).

**Priority.** P2 · occasional · M.

---

### 6.16 Settings tabs (individual)

| Tab | Observed issues | Recommendation | Priority |
|---|---|---|---|
| **Pi CLI** (`12`) | 2 cards with blue borders and filled buttons, 6 neutral, 1 red-bordered (MCP), with no legend. "Gestisci" in red. The output console is far below the fold and its empty message sits at the bottom of the box. Running a command requires scrolling to see its output **[RISK]**. | One card style. Mark the recommended action with a "Consigliato" tag, not a border colour. Place the output console in a right column on wide widths, or auto-scroll it into view when a command runs. Neutral MCP styling. | P2 |
| **Pacchetti** (`13`) | A tiny unlabeled spinner fills the whole tab **[OBS]** (fake-pi caveat). There is no timeout or error path in view. | Skeleton rows + "Caricamento pacchetti…" + a timeout after N seconds with Riprova and an error detail. | P1 |
| **Daemon** (`14`) | "(D9)" jargon. "Riavvia Daemon" is a neutral button, and whether it confirms is **[NV]**. "Stato: Endpoint rilevato" vs Diagnostics "CONNECTED" disagree. | Remove the IDs. Explain the restart consequence ("Le sessioni in corso verranno riconnesse"). Use one status vocabulary. | P2 |
| **Aspetto** (`15`, `23`) | Three theme selects (active, default dark, default light) plus a "system" toggle is redundant and confusing. The info box repeats the selected values. The language field is taller than the other selects. Two adjacent buttons have different styles. "Statistiche nerd" is informal for a toggle label. | One "Tema" control: Sistema / Chiaro / Scuro, and a theme select per mode shown only as needed. Remove the info box. Use uniform 40px fields. | P2 |
| **Privacy** (`16`) | Mostly empty. The bullets are low-contrast 12px. | Merge into Diagnostics or Generale as a short section. | P3 |
| **Diagnostica** (`17`) | `CONNECTED` and `DISABILITATA` are full-width filled bars that look like inputs. "D16" in the copy. | Inline status tag (dot + label) aligned left. Localize. | P2 |
| **Aggiornamenti** (`18`) | Clean. "(D16)" in the footer note. | Remove the ID. | P3 |
| **Terminale** (`19`) | The native-terminal app list stays active when "Terminale integrato" is selected. | Disable or collapse the dependent group until "nativo" is chosen (progressive disclosure, DESIGN §04). | P3 |
| **Accesso remoto** (`20`) | A danger callout for a missing optional binary while the feature is disabled. A filled primary install button inside a red box. The port line is accent mono text that looks like a link. The card inset and border differ from other tabs. | Neutral info callout until remote is enabled. Install as a secondary action. Use muted text for the port. Use the shared card. | P2 |
| **Agenti** (`21`) | The only tab with an explicit Save/Cancel bar. The empty state and the warning box duplicate one fact ("no subagent package"), and the warning is in English. Selects show "—". | Apply immediately like the other tabs, or show the save bar only when dirty. One empty state with an "Apri Pacchetti" action. Show the effective default ("Predefinito di Pi: <model>") instead of "—". | P2 |
| **Theme editor** (`22`) | A dense two-column dialog with an internal scroll. Heading in a small condensed face. A bright separator. "In corso" tag meaning unclear. | Larger preview using real app components (a pane header, a Git row, a chat turn). Group tokens with search. Token border separator. | P3 |

---

### 6.17 Compact layout (`09`, `10`, mobile `B3`–`B9`)

**Current state.** Below 900px: three full-width segmented tabs (Chat | File | Git Changes) + ⋮, an `IndexedStack`, and the session drawer.

**Issues.** **[OBS]** The selected tab differs only by a slightly lighter fill (`09`), so the selected state is weak. **[CODE]** The tab buttons are `GestureDetector`-based in the companion (`repository_workspace.dart:3244–3249`), so their keyboard access is at risk. **[OBS]** The pane header repeats the tab name ("GIT CHANGES" under the "Git Changes" tab, `B9`). **[OBS]** The status dot and labels are hidden in the compact header.

**Recommendations.** Selected tab: accent text + 2px accent underline or an inset accent bar, and `Semantics(selected: true)`. Drop the duplicate pane title in compact mode and keep only the pane actions. Keep the run status visible in the tab ("Chat ●").

**Priority.** P2 · compact users and mobile web · S.

---

### 6.18 Mobile web: pairing and offline (`A-unpaired`, `G-offline`)

**Issues.** **[OBS]** The unpaired screen has text only: no action, no QR or scan affordance, and no link to help. **[OBS]** Fallback fonts: system sans for the body, and **serif** for the "Riprova" button. **[OBS]** The offline spinner and the "Riprova" button together are ambiguous: is it already retrying? The copy says "Riprovo automaticamente…" yet also offers a button.

**Recommendations.** Ensure bundled fonts load before the fallback screens render, or use the font family explicitly. Add a primary action ("Come associare il dispositivo") and a short step list. On the offline screen, show "Nuovo tentativo tra 5 s · Riprova ora".

**Priority.** P2 · remote users · S.

---

## 7. Navigation & User Flow Assessment

### Model
One GoRouter route (`/` → `AppShell`) plus shell state (`app/router.dart:4–11`, `app/app_shell.dart:315–321`). This is appropriate for a desktop workbench. There are no deep links, which is acceptable because the target has no URL navigation need. The trade-off is that Settings tabs and panes cannot be bookmarked or restored from a URL on web.

### Documentation vs implementation

| NAVIGATION-MAP statement | Code reality | Severity |
|---|---|---|
| "User layout is persisted by `LayoutStore`" | Only pane visibility, sidebar collapsed and sidebar width are saved. **Pane weights, collapsed panes, compact selected pane and companion tab are not persisted** (`app/app_shell.dart:121–140`; `data/layout/layout_store.dart:23–38`) | P2: resizes are lost on restart. The user asked for resizable panes (D9 round 2) |
| "900–1439: chat plus one companion" | Only when Chat is visible. If Chat is hidden, all visible panes show (`app_shell.dart:808–830`) | Documentation nuance |
| "Command palette … `Ctrl/Cmd+K`" | Correct. But the palette advertises "Interrompi agente (Esc)", and Esc closes the palette instead | P3 |
| Breakpoints 900/1440/1560 | Match | — |

### Flow analysis

| Question (task brief) | Assessment |
|---|---|
| *Where am I?* | Good in the workspace: session title, cwd and branch are always visible. Weaker in compact mode (status hidden) and in Settings (the workspace context is gone). |
| *How did I get here?* | Session switching has no history or back. Opening a session from the rail cannot be "undone" except by re-selecting the previous one. **[OPP]** A "Sessione precedente" (Ctrl+Tab) action. |
| *What can I do?* | Many actions sit behind unlabeled icons (G-5). The palette covers only a subset (§6.13). |
| *What happens when I act?* | Git writes are well-explained. Sends, package loads and some Git errors are not (G-1). |
| *How do I go back?* | Escape is **not uniform**. It interrupts the agent in the composer, closes menus and search, but does not close Settings or Review mode and is not an explicit drawer handler (`composer.dart:2229–2232, 2282–2293`; `settings_view.dart:745–754`; `session_changes_pane.dart:291–303`). **P2.** |
| *How do I reach key features?* | The context drawer (model, compaction, tree) hides behind a sliders icon. Review Changes appears only when eligible and only as a composer icon. Its eligibility is invisible otherwise. **P2.** |

### Unreachable, redundant or orphaned
- No orphaned Settings tabs (`settings_view.dart:771–810`).
- **Redundant:** model, thinking and context controls exist in both the composer chips and the context drawer. Context usage exists in the header and the drawer. Search exists in the rail top and the rail footer. Quick links appear twice in the browser.
- **Hidden:** Review Changes has no entry when there are no agent changes, and no explanation. The workspace drawer is reachable only from a title-bar icon. Folder context menus exist only on right-click (`sessions_sidebar.dart:786–840, 1499–1538`).

### Destructive-action safety
Discard, session delete, repository remove (typed confirmation for delete-all) and package remove are confirmed **[CODE]** (`session_actions.dart:168–380`; `settings_view.dart:426–443`). Only hide-repository has Undo. **[OPP]** Stage and unstage are reversible and could skip confirmations entirely. Discard could move content to a recoverable stash ("Annulla" snackbar for 10s). That would make the action safer than a modal confirmation.

---

## 8. Desktop & Responsive Assessment

### Window management
- **[CODE]** The minimum is **680×480** (`main.dart:23–45`). The initial size is 1280×720 (runners) or a persisted default of 1100×720 (`data/window/window_state_service.dart:19–25`). Windows and macOS use a custom title bar with caption buttons. Linux keeps the native one.
- **[RISK]** At 680px the compact layout applies. At 480px height, the chat pane must fit the title bar (42) + tab bar (44) + session header (~80) + composer (~120), which leaves under 200px for the transcript. Consider a minimum height of 560px, or collapse the session header into the title bar at short heights.
- **At 1280×720** **[OBS]** (`captures-r2/r2-01-workspace-1280x720.png`; harness content 1264×711): medium layout shows chat (~720px) and one companion (~526px), with File/Git Changes tabs in the companion title bar; no sessions rail or triptych. Session header and unified composer controls fit. The transcript is mostly empty in this captured state; the repository list reaches the lower viewport edge but is scrollable. At this width, both repository and Git cannot be co-visible. **[OPP]** Allow 3 panes from about 1280px when the session rail is collapsed; the current ≥1440 threshold excludes common laptop widths.
- **At 1440×900** **[OBS]** (`captures-r2/r2-02-workspace-1440x900.png`; 1424×891): still medium layout because actual width is 1424px, below the 1440 breakpoint. Chat (~816px) + one companion (~608px), no sessions rail or triptych. Header and composer fit; the empty transcript leaves substantial unused vertical space. **[CODE]** Source uses 900–1439 for chat + one companion and adds the rail at 1560 (`app_shell.dart:322, 741–830`).
- **At 1920×1080** **[OBS]** (`captures-r2/r2-03-workspace-1920x1080.png`; 1904×1071): full Bento triptych plus sessions rail: rail ~280px, repository ~500px, chat ~690px, Git ~380px. All panes, session header and composer fit. Repository rows are compact; long Git paths/meta still truncate in the narrowest pane (`captures-r2/r2-08-hover-git-row.png`). The rail shows one collapsed repository row, leaving most of its height empty (`captures-r2/r2-09-hover-session-row.png`).
- **[OBS]** Settings at the 1280×720 harness size (`captures-r2/r2-04-settings-1280x720.png`): title and all tabs fit; two-column command cards are centered with broad side margins and extend close to the bottom without visible clipping.
- **[RISK]** Panes have no pixel minimum. Only a 15% weight floor applies, or the pane collapses (`app_shell.dart:1294–1320`). At 1440px, 15% ≈ 216px, which is narrower than the browser toolbar needs (the overflow in `25`).
- D9 round 2 reported multi-second stalls on minimize/restore. Round 4 reported them improved. **[RISK]** `AppShell` reads `MediaQuery.sizeOf` and rebuilds the shell on every resize frame (`app_shell.dart:320–329`). Pane subtrees are not isolated with `RepaintBoundary` or const boundaries. Watch this during live resize.

### Desktop interactions

| Aspect | Status |
|---|---|
| Hover states | Present on most rows via InkWell/hover colour. Ripple is disabled globally (`NoSplash`, `theme_spec.dart:367`). OK for desktop. |
| Pressed states | Custom 0.97 scale only on 3 call sites (`ui/precision.dart:26–37`). Other buttons have colour-only press feedback. **[OPP]** `better-ui` asks for 0.96 / 150ms ease-out applied consistently to buttons, never to rows or disabled controls. |
| Right-click | Files, sessions and repository folders: yes. Git rows, review rows, folders in the file tree, transcript messages: **no**. P3. |
| Keyboard shortcuts | Ctrl+K, Ctrl+Shift+B, Enter/Ctrl+Enter, Esc (composer), Ctrl+F (editor), terminal keys. **Missing:** Ctrl+N (new session), Ctrl+, (settings), Ctrl+S (save, **[NV]**), pane focus (Ctrl+1/2/3), pane toggle, next/previous session. P2. |
| Focus management | No `FocusTraversalGroup`/`FocusableActionDetector` anywhere (`[CODE]`). Tab order follows the widget tree across all panes. No custom focus colour is defined in the theme, so focus visibility relies on Material defaults, which are subtle on dark surfaces **[NV]**. P1. |
| Drag and drop | File drop on chat with opacity/scale feedback (`features/transcript/chat_drop_target.dart:67–75`). Pane dividers drag. There is no keyboard alternative for the pane dividers, except the sidebar divider, which has `Semantics.onIncrease/onDecrease` (`app_shell.dart:1094–1112`). P2. |

### Information density
- **[OBS]** Git rows remain tall (~56px) with two metadata lines; long paths and metadata truncate (`captures-r2/r2-08-hover-git-row.png`). Repository tree rows are denser (~28px). At 1904px the sessions rail still shows only one collapsed repository row, leaving a large blank area (`captures-r2/r2-09-hover-session-row.png`).
- **[OBS]** At 1264px and 1424px the chat transcript occupies a large blank canvas in these empty-session captures, though the session header and full composer fit. Settings at 1264px fits its tabs and two-column cards, but uses only the central portion of the window (`captures-r2/r2-04-settings-1280x720.png`).
- Over-packed: the title-bar icon cluster, the repository header (5 icons), the browser header (three control rows in 290px).
- **Recommendation:** adopt two density tiers from DESIGN ("balanced"): *list rows* at 28px and *form rows* at 40px, and use the tokens everywhere.

---

## 9. Interaction & Accessibility Assessment

### Component state coverage

| State | Observed / code status |
|---|---|
| Default / hover | Round 2 hover captures show a grey fill without a ring (`r2-06`–`r2-11`). |
| Focus | **Weak.** Round 2 Tab captures show no crisp focus ring on any of 8 steps; custom `GestureDetector` controls are not focusable: companion tabs (`repository_workspace.dart:3244–3249`), command-chip remove (`features/composer/command_chip.dart:153–160`), inline file links (`features/transcript/rich_content.dart:728–732`). **P1.** |
| Pressed | Partial (see §8). |
| Selected | Filter chips and compact tabs have weak selection contrast (`07`, `09`). Tree selection is not captured. |
| Disabled | Clear for Crea/Commit (`03`, `42`). The disabled "Salva" is visually too heavy (`27`). Git actions are disabled while Pi runs, with an explanation (`40`). Good. |
| Loading | Spinner only. No labelled or skeleton states (`13`; `sessions_sidebar.dart:965–967`; `repository_workspace.dart:811–823, 2943–2955`). **P2.** |
| Success | Snackbars (`ui/frame_snack_bar.dart`). The commit result is not captured **[NV]**. |
| Warning / Error | Callouts exist (`20`, `21`). Raw exceptions leak (G-1). The confirmed P0 provider-error path is fixed in round 3 (§14.1). **P1 remains for raw exceptions.** |
| Empty | Present but without actions (G-6). |

### Accessibility checklist (ui-ux-pro-max pre-delivery list, desktop-relevant items)

| Check | Result |
|---|---|
| Text contrast ≥4.5:1 | ✅ Muted text on surface is about 5.0:1 dark and 5.9:1 light (`packages/pi_frame_theme/lib/src/theme_tokens.dart:131–199`). ⚠️ Accent text on tinted chips and danger-on-dark callouts were not measured **[NV]**. |
| Non-text contrast ≥3:1 for input boundaries | ❌ Borders are 1.4–1.5:1. Inputs whose fill matches the surface rely on them. **P2.** |
| Colour not the only cue | ✅ Status badge + label, Git status text. ⚠️ The "+0 −0" diff stats rely on green/red, though they have signs. ⚠️ The compact-mode connection status is hidden entirely. |
| Icon controls have accessible names | ⚠️ 110 `IconButton`s, mostly with tooltips. At least one without (`session_tree_dialog.dart:108`). Custom gesture controls lack `Semantics(button: true, label:)`. |
| Focus visible and order logical | ❌ No crisp focus ring in the round 2 Tab captures, and the traversal order jumps across panes (§15.3 N1, P1-17). **P1.** |
| Target size | ⚠️ 20×20 folder button, compact 0-padding Git row actions (`repository_workspace.dart:2611–2635`), 28px tree rows. Desktop guidance: ≥24×24 (WCAG 2.5.8 AA). **P2.** |
| Text scaling | ⚠️ Not suppressed (good), but fixed 42/44/28px heights risk clipping (`app_shell.dart:440–443, 1329–1337`). **P3.** |
| Reduced motion | ✅ Shimmer, working-session dot and subagent pulse are static under reduced motion (§14.2). Other motion gaps are listed in §10. |
| Live regions | ✅ The status badge is a live region (`features/status/agent_status_badge.dart:85–88`). ⚠️ Errors in snackbars are not confirmed as announced **[NV]**. |
| Error prevention | ✅ Typed confirmation for delete-all, discard preview. ⚠️ Commit allowed with an empty message in appearance **[NV]**. |
| Cognitive load | ⚠️ Three places for model and context. Three theme selects. Ten flat settings tabs. |

### Where users may misunderstand or make mistakes
1. Thinking the prompt was sent when a non-streaming send failed (G-1). **Status: the confirmed P0 provider-error path was fixed in round 3 (§14.1).**
2. Picking the wrong Git row because file names are truncated away (§6.10).
3. Hitting discard instead of stage on dense row actions, then losing work after confirming out of habit (§6.10).
4. Reading the red Remote callout or the red MCP card as errors that need fixing (§5.1).
5. Not finding how to steer during a run, because the composer hides (§6.7).
6. Losing the main chat context when the side conversation covers it (§6.12).

---

## 10. Motion Design Assessment

### Lens weighting (design-motion-principles)
PiFrame is a **productivity tool used for hours per day**. **Emil (primary):** restraint, <300ms, no animation on keyboard-initiated or high-frequency actions. **Jakub (secondary):** polish on panels, dialogs and state changes. **Jhey (selective):** only first-run and empty states. This agrees with DESIGN §05 and §07.

### Existing motion inventory (code)

| Motion | Location | Duration | Curve | Trigger | Reduced-motion |
|---|---|---:|---|---|:--:|
| Launch reveal (opacity 0.82→1, slight slide) | `ui/precision.dart:61–124` | 620ms | `enterCurve` | First frame, ends on input | ✅ |
| Startup assemble overlay (painter, audio cues, opaque) | `ui/startup_assemble_animation.dart:40–137` | 1,400ms | `easeOutBack` + linear | Desktop launch | ✅ (skipped) |
| Press scale 0.97 | `ui/precision.dart:26–37` (3 call sites) | 120ms | `enterCurve` | Pointer down | ✅ |
| **ShimmerBorder activity sweep** | `ui/shimmer_border.dart:38–58` | 3,600ms cycle | painter | Composer active | ✅ Static under reduced motion |
| **Working-session pulse** | `features/sessions_sidebar/sessions_sidebar.dart:1098–1118` | 1,400ms loop | `easeInOut` | Running session | ✅ Static under reduced motion |
| **Subagent activity pulse** | `features/transcript/subagent_panel.dart:425–482` | 1,600ms loop | linear | Running agent | ✅ Static under reduced motion |
| Command-chip intro (scale/opacity/glow) | `features/composer/command_chip.dart:29–79` | 520ms | `easeOutBack` | Chip insert | ✅ |
| Chip hover/remove (incl. rotation) | `command_chip.dart:85–177` | 120–160ms | `easeOut` | Hover | ❌ |
| Composer height tween / box switch | `features/composer/composer.dart:53–58, 1797–1832` | 240ms height tween (`FrameMotion.panel`) | `enterCurve` | Content/mode change | ⚠️ Reduced-mode behavior not verified |
| Composer inline control swap | `composer.dart:2413–2425` | 150/180ms | `easeOutCubic` | State change | ✅ |
| Slash menu enter / row highlight | `features/composer/slash_menu.dart:44–93` | 140/120ms | `easeOutCubic`/`easeOut` | Menu open/arrow | ✅ (enter) |
| Drop-target overlay | `features/transcript/chat_drop_target.dart:67–75` | 200ms | ease in/out cubic | Drag enter/exit | ❌ |
| Status badge | `features/status/agent_status_badge.dart:87–92` | 120ms | `easeOutCubic` | Status change | ✅ |
| Thinking, tool-card and tool-step expansion | `features/transcript/thinking_block.dart:157–163`; `tool_timeline/tool_card.dart`; `transcript/steps_group.dart`; `ui/motion.dart` | 160ms (`FrameMotion.small`) | `enterCurve` | Expand | ✅ `FrameExpandable` cross-fades |
| Todo / activity overlay size | `features/transcript/todo_panel.dart:469–473`; `transcript_view.dart:2019–2023` | 200ms | `easeOutCubic` | Expand | ❌ |
| Subagent panel size / row enter | `subagent_panel.dart:144–268` | 220/240ms | `easeOutCubic` | Resize/new row | ❌ |
| Companion tab indicator | `repository_workspace.dart:3245–3256`; `session_changes_pane.dart:115–127` | 140ms | default | Tab switch | ❌ |
| Transcript auto-scroll | `transcript_view.dart:384–398` | 240ms | `easeOutCubic` | Scroll to bottom | ✅ |
| Dialogs | Material default | ~150–200ms | default | Open/close | framework |
| Command palette, branch picker | `command_palette.dart:38–46`; `branch_picker_dialog.dart:24–35` | none | — | Keyboard/click | n/a ✅ |
| Theme change | `main.dart` (`themeAnimationDuration: FrameMotion.panel`) | 240ms | `AnimatedTheme` | Theme toggle | ⚠️ Reduced-mode behavior not verified |

**Tokens [CODE]:** `FrameTokens` provides `pressDuration` 120ms, `panelDuration` 240ms, `enterCurve` `Cubic(0.23,1,0.32,1)` and `panelCurve` `Cubic(0.32,0.72,0,1)` (`packages/pi_frame_theme/lib/src/theme_tokens.dart:121–124`). Round 3 added `ui/motion.dart` (`FrameMotion`, `FrameEnter`, `FrameExpandable`) and moved selected transitions to shared timings. The initial audit counted 32 hard-coded durations (16 distinct values, 50–3,200ms) and 25 `Curves.*` uses (6 curves); remaining literals still bypass the shared motion tokens.

### Findings (ordered by severity)

| # | Severity | Finding | Principle / impact |
|---|---|---|---|
| M-1 | **P1 (better-ui HIGH)** | Three activity loops (shimmer, session pulse, subagent pulse) originally ignored `disableAnimations`. **Status: fixed in round 3 (§14.2); all three are static under reduced motion.** | Reduced motion is mandatory (all three skills). A continuous peripheral loop next to reading text is also a distraction (anti-checklist: "pulsing indicators"). WCAG 2.2.2 applies to auto-moving content >5s. |
| M-2 | P1 | **Motion gaps in primary UI:** pane show/hide/collapse, review-mode entry/exit, diff open, side panel, welcome→workspace and companion content originally lacked transitions (`app_shell.dart:842–860, 1204–1236, 90–123, 320–330`). **Status: partial in round 3 (§14.2): new panes fade/settle, pane width still snaps; side panel slides in but overlays chat; diff remains modal.** | Checklist: "conditional panels that snap in/out" is Critical. Spatial continuity is lost where compartments still snap or overlay one another. |
| M-3 | P2 | No exit motion on several entering elements (subagent rows, drop overlay exits at the same speed as it enters). Enter and exit are symmetric (200ms both). | `better-ui`: exits shorter and smaller than enters. |
| M-4 | P2 | Inconsistent expand behaviour: thinking animates, while tool cards and step groups originally snapped. **Status: partial in round 3 (§14.2): tool cards and steps now use `FrameExpandable`.** | Same interaction behaved two ways; see the remaining open motion items in §14.5. |
| M-5 | P2 | Composer height originally used 280ms `easeInOutCubic`. **Status: fixed in round 3 (§14.2): 240ms `FrameMotion.enterCurve`.** | The height tween now uses the shared short ease-out timing. |
| M-6 | P2 | The startup assemble overlay is opaque for 1.4s with audio cues on every desktop launch. It is dismissible by input, but a first-time user does not know that. | Frequency gate: launch happens several times a day for this audience. That is acceptable once (first run) and should be skippable or set in Settings. |
| M-7 | P3 | **Corrected in round 3 (§14.3):** `AnimatedTheme` interpolates the whole `ThemeData`; there is no per-element colour smear. The duration is now 240ms. | The original recommendation to disable the transition was based on an overstated finding. |
| M-8 | P3 | Dialog transitions differ: the palette and branch picker are instant, while the others use the Material default fade/scale. | Pick per frequency: keyboard-launched = instant (correct), click-launched = one shared `dialog` token. |
| M-9 | P3 | Chip-remove hover rotates the ✕ icon. | Decorative motion on a high-frequency hover. Colour only. |
| M-10 | P3 | Indeterminate spinners everywhere, including tiny ones (`13`). No determinate or progress text. | Loading feedback should match the wait (ui-ux-pro-max *Loading Indicators*). |

Working well: one-shot animations are gated. The palette and branch picker are correctly instant. Press feedback stays at a subtle 0.97/120ms. The slash menu at 140ms is fast and directional. There is no streaming text theatre.

### Proposed motion token set (strategic, aligned with existing tokens)

| Token | Duration | Curve | Use |
|---|---:|---|---|
| `instant` | 0ms | — | Keyboard-initiated overlays, tab switches, tree expand by key |
| `micro` | 120ms | `enterCurve` | Hover/press colour, selection highlight, status cross-fade |
| `small` | 160ms (exit 120ms) | `enterCurve` | Expand/collapse rows, chips, menus |
| `panel` | 240ms (exit 180ms) | `panelCurve` | Pane show/hide, side panel, drawers, diff in pane |
| `dialog` | 180ms (exit 120ms) | `enterCurve` | Click-launched dialogs: opacity + scale 0.97→1 |
| `firstRun` | 300ms + 100ms stagger | ease-out | Welcome first run, empty states only |

Under reduced motion, every token maps to an **opacity cross-fade of ≤150ms** (no translate, scale or size), and loops become static.

### Specifications for significant proposed animations

**A. Pane show / hide / collapse (Bento compartments) — Round 3 status: Partial (§14.2).**

| Property | Specification |
|---|---|
| Trigger | Toggle pane (title bar, palette, shortcut), collapse via divider, review-mode enter/exit |
| Element | The affected pane and its neighbours |
| Animated properties | Pane width (animated flex weight via `TweenAnimationBuilder` on weights), content opacity 0→1 after 60% of the width |
| Duration | 240ms show, 180ms hide; `instant` when keyboard-initiated |
| Easing | `panelCurve` `Cubic(0.32,0.72,0,1)` |
| Behaviour | Neighbours slide to make room. Content does not reflow mid-animation: lay out at the final width and clip with `ClipRect` |
| UX rationale | Spatial continuity: the user sees where the compartment came from and went. This matters most for review mode, which swaps Repository for Review |
| Reduced motion | Cross-fade 150ms at the final layout |

**B. Diff open inside the Git companion (replaces the modal) — Round 3 status: Not done (§14.2).**

| Property | Specification |
|---|---|
| Trigger | Click/Enter on a Git row |
| Element | Companion body: list → diff view |
| Animated properties | Outgoing list opacity 1→0 and x 0→−8px. Incoming diff opacity 0→1 and x 8→0px |
| Duration | 180ms in, 120ms back |
| Easing | `enterCurve` |
| Behaviour | The header changes to "← Modifiche · file.dart (2/5)". Alt+↓ moves to the next file with no animation (keyboard) |
| UX rationale | Keeps chat visible and shows navigation direction (drill-in vs back) |
| Reduced motion | Cross-fade 120ms |

**C. Side conversation split — Round 3 status: Partial (§14.2).**

| Property | Specification |
|---|---|
| Trigger | Ctrl+Shift+B (instant) / palette or click (animated) |
| Element | Side panel and main chat column |
| Animated properties | Side panel width 0→40%, main column narrows. Side content opacity after 50% |
| Duration | 240ms open, 180ms close |
| Easing | `panelCurve` |
| UX rationale | Replaces the overlay that clipped chat (`30`). The split communicates "parallel thread", not "modal" |
| Reduced motion | Cross-fade |

**D. Agent activity indicator — Round 3 status: Done with a different design (§14.2): the composer ring sweeps in normal motion, and the session/subagent cues keep their normal-mode pulse; all three are static under reduced motion.**

| Property | Specification |
|---|---|
| Trigger | Pi run starts/stops |
| Element | Composer border, session row status, subagent row |
| Animated properties | Border colour neutral→accent (one transition). Status dot: a static ring + "In esecuzione" label. An optional *single* 2s determinate-looking sweep at run start, then static |
| Duration | 120ms colour transition. No loop |
| Easing | `enterCurve` |
| UX rationale | The state stays visible through colour + label. It removes a continuous peripheral motion that competes with reading for minutes at a time (Emil frequency gate, anti-checklist "pulsing indicators") |
| Reduced motion | Colour change only (already static) |

**E. Expand/collapse of tool, step and thinking groups (unify) — Round 3 status: Done for tool steps and tool cards; thinking blocks already animated (§14.2).**

| Property | Specification |
|---|---|
| Trigger | Click/Enter on the summary row |
| Element | Group body |
| Animated properties | Height via `AnimatedSize` + opacity. Chevron rotation 0→180° |
| Duration | 160ms expand, 120ms collapse. `instant` when keyboard-initiated |
| Easing | `enterCurve` |
| UX rationale | One behaviour for all intermediate blocks (fixes M-4). Short enough for a high-frequency action |
| Reduced motion | No size animation, 100ms fade |

**F. Stage / unstage row transfer — Round 3 status: Partial (§14.2): rows fade in, but do not travel between groups.**

| Property | Specification |
|---|---|
| Trigger | + / ⊖ / Space on a Git row |
| Element | The file row |
| Animated properties | Row opacity 1→0 and y 0→−4px in the source group, then opacity 0→1 and y 4→0 in the target group. Group counts update instantly |
| Duration | 120ms out + 160ms in |
| Easing | `enterCurve` |
| UX rationale | Confirms *where* the file went. This is useful when the groups are long |
| Reduced motion | Instant move. The count change is the static cue |

**G. Snackbar / inline error — Round 3 status: Not changed; Material default (§14.2).**

| Property | Specification |
|---|---|
| Trigger | Action result |
| Element | Snackbar (bottom-right) or inline error line |
| Animated properties | Opacity + 8px rise in. Opacity out |
| Duration | 180ms in, 120ms out. Auto-dismiss 4s (success), persistent with ✕ (error) |
| Easing | `enterCurve` |
| UX rationale | Feedback that is noticed but not alarming. Errors stay until dismissed |
| Reduced motion | Fade only |

**H. Theme switch — Revised in round 3 (§14.3).** `AnimatedTheme` interpolates the whole `ThemeData`; the per-element smear finding was overstated. `themeAnimationDuration` is now 240ms (`FrameMotion.panel`), so the transition stays short without disabling it.

---

## 11. Recommended Design Direction

These principles come from PiFrame's own DESIGN.md and its actual use. They do not introduce a new style.

1. **Session-bound workbench first.** The session identity (title · cwd · branch · run state) is the anchor of every view. It stays visible in compact mode and in Settings (a sheet, not a replacement view).
2. **Quiet surfaces, meaningful colour.** Neutral slate surfaces, 1px borders, 6/10/14 radii. Accent marks selection and the primary action only. Warning and danger appear only when something actually needs attention. Remove the decorative red and yellow uses (Settings indicator, MCP card, Side tag, Remote callout).
3. **Flat compartments, not nested cards.** One border level per Bento pane. Inside panes, use rows, dividers and spacing, not inner cards (chat header, assistant turn, step group, Settings info boxes).
4. **Two densities, tokenized.** 28px list rows (tree, Git, sessions, activity) and 40px form rows (settings, dialogs). Spacing 4/8/12/16/24/32. Type 11/12/13/14/16/20/28, with no literals below 11px.
5. **Name first, path second.** Every file or session list leads with the distinguishing name and middle-truncates paths.
6. **Every action closes the loop.** Pending → result state for sends, Git writes, package and CLI commands, with localized, actionable copy. Raw exceptions appear only in "Dettagli".
7. **Keyboard parity.** Every pane, tab and row action is focusable, has a visible focus ring (2px accent, 2px offset) and is reachable from the palette. Escape always means "close the topmost layer".
8. **Motion as spatial explanation, not decoration.** Animate compartment changes and drill-in/out (≤240ms). Keyboard and high-frequency actions are instant. Activity cues may animate in normal motion, but become static under reduced motion; other reduced-motion behavior uses short cross-fades.
9. **One component vocabulary.** Shared PaneHeader, Section, ListRow, StatusTag, IconAction, EmptyState and Callout widgets in `lib/ui/`, used by every feature, so "the same detail done two ways" cannot recur.

---

## 12. Prioritized Improvement Roadmap

Complexity: **S** ≤1 day · **M** 1–3 days · **L** >3 days. Frequency: how often users meet the issue.

### P0 — Critical

| ID | Finding | Affected | Evidence | User impact | Frequency | Cx | Expected improvement |
|---|---|---|---|---|---|---|---|
| P0-1 | Ordinary prompt-send failure shows no error — **fixed in round 3 (§14.1); confirmed by maintainer in the running app** | Composer / session reducers | **[CODE]** `domain/session/session_reducer.dart`, `snapshot_reducer.dart`, `session_state.dart` | User could not tell why the message did not reach Pi. This is the core job | Every failed send | S | Failure visible with Retry; user entry marked failed |

### P1 — High

| ID | Finding | Affected | Evidence | User impact | Frequency | Cx | Expected improvement |
|---|---|---|---|---|---|---|---|
| P1-1 | Git paths end-truncated, file names hidden | Git Changes | **[OBS]** `07`, `08` | Wrong-file review/stage | Every Git review | S | Filename-first rows |
| P1-2 | Git rows 56px with redundant meta, 9px text | Git Changes | **[OBS]** `07`, `43`; **[CODE]** `repository_workspace.dart:2595–2599` | Excess scrolling, illegible meta | Every Git review | S | 2× more rows visible, legible status |
| P1-3 | Diff opens as modal, hides chat, no file navigation | Git Changes | **[OBS]** `44` | Context loss, slow multi-file review | Frequent | M | In-pane diff with next/previous |
| P1-4 | Browser companion overflow and clipped controls | Web Browser | **[OBS]** `25`, `26`, `27`, `30` | Address bar and controls unusable at default width | When browser used | S–M | One-row toolbar + min width |
| P1-5 | Side conversation overlays and clips chat | Side panel | **[OBS]** `30` | Main thread unreadable while side is open | Occasional | M | True split |
| P1-6 | Composer hidden behind hover during streaming | Composer | **[OBS]** `40` | Steering hard to discover, not keyboard/touch friendly | Every run | M | Always-visible field + status line |
| P1-7 | Streaming → settled layout shift on every response | Transcript | **[OBS]** `40` → `41` | Visual jump at completion | Every response | S–M | Stable geometry |
| P1-8 | Editor uses a proportional font, no line numbers, link styling | Repository editor | **[OBS]** `27` | Unreliable editing and line references | Frequent | M | Code-grade editor surface |
| P1-9 | Infinite loops ignore reduced motion — **fixed in round 3 (§14.2)** | Composer, Sessions, Subagents | **[CODE]** `ui/shimmer_border.dart`; `sessions_sidebar.dart`; `subagent_panel.dart` | Accessibility failure, distraction | Every run | S | Activity is static under reduced motion |
| P1-10 | Custom controls not keyboard-focusable; no traversal groups; no crisp focus ring in round 2 captures | Companion tabs, chip remove, file links, panes | **[OBS]** `captures-r2/r2-12`–`r2-19`; **[CODE]** `repository_workspace.dart:3244–3249`; `command_chip.dart:153–160`; `rich_content.dart:728–732` | Keyboard users blocked from some actions | Global | M | Keyboard parity |
| P1-11 | Packages tab: unlabeled tiny spinner, no timeout | Settings › Pacchetti | **[OBS]** `13` (fake-pi caveat) | User cannot tell if it is loading or broken | When managing packages | S | Labelled skeleton + timeout/error |
| P1-12 | Raw exceptions shown to users | Git, branch, packages | **[CODE]** `repository_workspace.dart:41, 246, 2087`; `settings_view.dart:233–240`; DESIGN round-2 quote | Confusing, non-actionable errors | On errors | M | Localized messages + Details |
| P1-13 | Hard-coded font sizes (8–10.5px) override the type scale | Global | **[CODE]** `tool_card.dart:436–494`, others | Illegible metadata, inconsistent hierarchy | Global | M–L | Type tokens enforced |
| P1-14 | No shared UI primitives → same details done many ways | Global | **[CODE]** `lib/ui/` inventory; G-2 | Visual inconsistency keeps recurring | Global | L | Durable consistency |
| P1-15 | Sessions: repository must be expanded to reach sessions; tiny targets | Sessions rail | **[OBS]** `07`, `10`; **[CODE]** `sessions_sidebar.dart:749–758` | Slower critical *find/switch* flow | Many times a day | M | One-click session switch |
| P1-16 | Pane motion gaps (show/hide/review/diff snap) — **partial in round 3 (§14.2): A partial, B not done, C partial** | Workspace | **[CODE]** `app_shell.dart:842–860, 1204–1236` | Lost spatial orientation | Frequent | M | Complete remaining pane transitions; see Spec A/B/C |
| P1-17 | Tab order jumps across panes (composer → last Git row → sessions footer → last file row) | Global keyboard path | **[OBS]** `captures-r2/r2-12`–`r2-19` (§15.3 N1) | Keyboard users lose their place | Every keyboard session | M | Ordered `FocusTraversalGroup` per pane |
| P1-18 | Git discard dialog: "Annulla" (cancel) beside "Annulla modifiche" (discard), destructive action in accent colour | Git Changes | **[OBS]** `captures-r3/r5-11` (§15.3 N2) | Accidental, unrecoverable discard | Every discard | S | Rename to "Scarta modifiche", danger style, as in `r5-14` |

### P2 — Medium

| ID | Finding | Evidence | Cx |
|---|---|---|---|
| P2-1 | Decorative/semantic colour misuse (yellow tab indicator, red MCP card, red Side tag, danger callout for optional binary, danger context icon) | `12`, `20`, `30`, `05` | S |
| P2-2 | Internal IDs (D9, D16), English and raw-enum strings in the Italian UI | `14`, `17`, `18`, `21`, `29`, `34`; `strings_settings.dart:99, 238, 784` | S |
| P2-3 | Escape not uniform; no Escape for Settings or Review | `settings_view.dart:745–754`; `session_changes_pane.dart:291–303` | S–M |
| P2-4 | Pane weights and collapsed state not persisted | `app_shell.dart:121–140`; `layout_store.dart:23–38` | S |
| P2-5 | Command palette coverage, shortcut labels in titles, platform key labels, context-irrelevant items | `24`; `command_palette.dart:97–190`; `strings_shell.dart:301–303` | M |
| P2-6 | Settings IA: 10 flat tabs, mixed save model (Agents), three theme selects, status bars as inputs | `12`–`23` | M |
| P2-7 | Spacing and radius not tokenized (~45 radius literals, off-scale gaps) | `theme_tokens.dart:3–65`; `web_browser_pane.dart:347–555`; `remote_section.dart:524–548` | M |
| P2-8 | Input-boundary contrast 1.4–1.5:1 | Token values; `07` search fields | S |
| P2-9 | Hit targets <24px (folder +, Git row actions) | `sessions_sidebar.dart:749–758`; `repository_workspace.dart:2611–2635` | S |
| P2-10 | Empty states without actions; blank chat empty state; collapsed Git groups leave empty pane | `05`, `30`–`32`, `36`, `42`, `B9` | S–M |
| P2-11 | Title-bar icon ambiguity; context drawer hard to find; metadata in 3 places | `05`, `29` | S–M |
| P2-12 | Welcome screen emphasises create over resume; empty canvas | `01`, `02` | M |
| P2-13 | New-session dialog: premature busy state, value-like placeholder, no recents/validation | `03`, `04` | S–M |
| P2-14 | Commit dialog: one-line message, Commit looks enabled while empty | `46` | S |
| P2-15 | Git "writes disabled" banner causes layout shift | `40` | S |
| P2-16 | Session header nested card; cryptic "—/—" context | `05` | S |
| P2-17 | Compact tabs: weak selected state; duplicate pane titles | `09`, `B9` | S |
| P2-18 | Mobile web: font fallback (serif button), unpaired screen without action | `A-unpaired`, `G-offline` | S |
| P2-19 | Default 1280×720 window never shows the full triptych | Breakpoints `app_shell.dart:731–830` | M |
| P2-20 | Startup overlay 1.4s opaque with audio on every launch | `ui/startup_assemble_animation.dart:40–137` | S |
| P2-21 | Inconsistent expand motion (M-4 partial); composer height 280ms curve (M-5 fixed at 240ms in round 3); enter/exit symmetry remains | §10 M-3–M-5; §14.2 | S |
| P2-22 | Context drawer: contradictory usage text, double heading, overlay stacking | `29`, `31` | S |
| P2-23 | Missing desktop shortcuts (new session, settings, pane focus) | §8 | S–M |

### P3 — Low

| ID | Finding | Evidence |
|---|---|---|
| P3-1 | Mixed Material icon variants and sizes; `.gitignore` red branch icon | `app_shell.dart:190, 593`; `05` |
| P3-2 | Non-concentric nested radii (pane title bar inside pane frame) | `05`, `07` |
| P3-3 | Always-visible add-to-chat icon per file row; double-border search field | `05` |
| P3-4 | Off-state switches louder than on-state | `15`, `18` |
| P3-5 | Dialog size not fitted to content (MCP, tree, diff, branch list) | `28`, `31`, `32`, `44` |
| P3-6 | Missing right-click menus (Git rows, folders, messages) | `repository_workspace.dart:2568–2637, 3490–3534` |
| P3-7 | Theme-switch smear finding corrected in round 3 (§14.3); chip ✕ rotation; mixed dialog transitions | §10 M-7–M-9 |
| P3-8 | Six built-in themes vs two normative; stale "Catppuccin" comment | `theme_repository.dart:18–143`; `file_icon.dart:3–4` |
| P3-9 | Terminal-settings dependent options not disabled; Privacy tab nearly empty | `19`, `16` |
| P3-10 | Keyboard hint shown on touch devices; logo treatment differs desktop/mobile | `B-paired`, `01` |
| P3-11 | Fixed-height rows/headers vs text scaling | `app_shell.dart:440–443, 1329–1337`; `repository_workspace.dart:3546–3549` |

### Suggested sequencing
1. **Sprint 1, trust and core flow:** P0-1 (fixed), P1-1, P1-2, P1-4, P1-6, P1-9 (fixed), P1-11, P1-12, P2-2. Mostly S. Very visible.
2. **Sprint 2, system foundation:** P1-13, P1-14, P2-7, P2-8 (tokens + `lib/ui` primitives). Then migrate Git, Sessions and Settings to them, which addresses P2-1, P2-6 and P2-10 along the way.
3. **Sprint 3, workflow depth:** P1-3, P1-5, P1-7, P1-8, P1-15, P1-16, P2-3, P2-4, P2-5 (the motion token set lands here).
4. **Then:** the remaining P2 and P3 items, opportunistically.

---

## 13. Final Recommendations

1. **Close the remaining feedback loops.** The confirmed P0 send-failure path is fixed in round 3 (§14.1). Package loading, raw exceptions and hidden connection status remain opaque and directly affect the product promise of "trustworthy session control".
2. **Fix the Git review surface.** It is the second pillar of the Bento workbench and currently the weakest: truncated names, 56px rows, a modal diff and collapsed groups. Filename-first 28px rows and an in-pane diff turn it into the IDE-like flow the user asked for in D9.
3. **Enforce DESIGN.md §07 in code.** Add spacing and type tokens and 5–7 shared primitives. Without them, every new iteration will reintroduce the "same detail done two ways" inconsistencies documented in §4–§6.
4. **Make the keyboard path complete.** Focusable custom controls, a visible focus ring, a uniform Escape, palette coverage of all major actions and platform-correct shortcut labels. Expert Pi users are the primary audience.
5. **Keep motion accessible and consistent.** The three activity loops now become static under reduced motion (§14.2). Continue applying `FrameMotion` to remaining pane transitions, and retain the documented normal-motion activity cues.
6. **Review the round 2 evidence and capture only remaining gaps.** The 31 captures cover the target viewports, hover/focus, Packages steady state and slash/@ menus. Slow-stream mid-stream and the delete-session and Git-discard confirmations were captured in round 5 (`captures-r3/r5-*`); only Review Changes remains uncaptured. §15 contains the lead's own visual review and live harness verification. Further mobile-web captures are out of scope by maintainer decision.

### Next steps
- Track the remaining open §12 P0/P1 rows; P0-1 and P1-9 are fixed, and P1-16 is partial in round 3.
- Present this report and the round 2 captures to the human reviewer in the ongoing Design Director D9 round; §15 contains the lead's review and live harness verification. This audit does **not** constitute D9 approval.
- Update `docs/ui-exploration/NAVIGATION-MAP.md` to correct the layout-persistence statement (§7) when the code changes. This audit did not modify it.

---

## 14. Round 3 addendum: implementation status

This section records what was changed after the audit, what was verified, and what remains open. The findings above are unchanged except where this section corrects them.

### 14.1 P0 confirmed and fixed
- **Confirmed in the running app** by the maintainer: the message appears, the status returns to idle, and no reply or error appears. The trigger is a provider or model error.
- **Root cause (corrects §6.7 item 1):** the failure was not in the composer. When the provider ends a turn with an empty assistant message (`stopReason: error`, `errorMessage`), the reducers stored that error only on a *previous* assistant entry. Before any reply there was none, so the reason was dropped and the user message was never marked failed. The transcript's existing failure UI (red border, "Invio non riuscito", retry) only fires for that marker.
- **Fix:** `applyTerminalStop` in `domain/session/session_state.dart`, used by `session_reducer.dart` (live) and `snapshot_reducer.dart` (replay). A provider error with no prior reply marks the user message with `sendError`. An error that interrupts a reply shows "Risposta interrotta da un errore" under the assistant message (`features/transcript/transcript_view.dart`). A user abort (`aborted`) is not reported as an error.
- **Tests:** `test/transcript_grouping_merged_final_test.dart` (+3: live, replay, aborted). All 15 tests in the file pass.

### 14.2 Reduced motion and motion pass

| Item | Status | Where |
|---|---|---|
| Reduce-motion toggle in Appearance | **Done** | `features/settings/settings_view.dart` (key `settings-reduced-motion-switch`), `data/motion/reduced_motion_settings.dart` (persisted in `~/.piframe/`) |
| OS setting honoured, combined with the toggle | **Done** | `main.dart`: one `MediaQuery.disableAnimations` flag, so every existing check follows both sources |
| Shared motion timings and curves, reduced-motion widgets | **Done** | `ui/motion.dart`: `FrameMotion`, `FrameEnter`, `FrameExpandable` |
| A. Pane show/hide | **Partial**: new panes fade in and settle (`FrameEnter`). The pane width itself still snaps. Animating width needs a change to the flex layout that was not done. |
| B. Diff open in the Git companion | **Not done**: the diff is still a modal. |
| C. Side conversation | **Partial**: the panel slides in from the right. It still overlays the chat rather than splitting it. |
| D. Activity indicator (replaces loops) | **Done, with a different design from the audit**: composer ring sweeps once per 3.6s cycle, accelerates and settles, then rests (`ui/shimmer_border.dart`). Working-session dot and subagent pulse keep their normal-mode animation. All three are static under reduced motion. |
| E. Expand/collapse | **Done** for tool steps and tool cards (`FrameExpandable`). Thinking blocks already animated. |
| F. Stage/unstage | **Partial**: rows fade in where they appear (`repository_workspace.dart`). The row does not travel between the Staged and Changes groups. |
| G. Snackbar | **Not changed**: Material default. |
| H. Theme switch | **Revised**: see 14.3. |
| Composer height tween | **Done**: 280 ms `easeInOutCubic` → 240 ms `enterCurve`. |
| Dialog transitions unified (M-8) | **Not done.** |
| Spinners | Indeterminate spinners are kept under reduced motion on purpose: they signal work in progress. |

### 14.3 Correction to M-7
§10 said the theme switch "smears" and recommended disabling the transition. That was overstated. Flutter's `AnimatedTheme` interpolates the whole `ThemeData` in one animation, so colours do not smear per element. The app now sets `themeAnimationDuration` to 240 ms to keep the change short and consistent with the panel token.

### 14.4 Verification
- `flutter analyze`: no issues.
- `flutter test` (full app): all tests pass. There are 698 passing tests and 3 skipped. The skips were there before this work. One pre-existing Appearance test needed `ensureVisible`, because the new section pushes the step-grouping switch below the fold in the 800×600 test viewport.
- New tests: `test/motion_reduced_test.dart` (7 tests): setting persistence, `FrameEnter` in both modes, `FrameExpandable` build-on-first-open, and the shimmer ring in both modes.
- Captures of the states the audit could not see are in `captures-r2/` (31 PNGs). Points they confirmed: no crisp focus ring is visible on any of 8 Tab steps; hover is a grey fill with no ring; the command palette and new-session field have a blue outline; slow-stream r2-26 was captured after completion, so mid-stream was not captured.
- Harness verification (`captures-r3/`): the Appearance toggle was switched on and off in the real app, stayed on after changing tabs, and the logs showed no Flutter exceptions. Two subagent attempts did not reach a streaming session (`workspace-*-motion.png` show only the launch screen). The lead then verified the composer ring live during a stream in both modes (§15.2).

### 14.5 Still open
Pane width transitions (A), in-pane diff (B), a true split for the side panel (C), Git row travel (F), dialog transitions (M-8), the keyboard and focus work (P1-10), hit-target sizes (P2-9), and the design-token enforcement (P1-13, P1-14) are not done. The composer ring was verified live (§15.2); the working-dot and subagent pulses were not observed live. These are listed in §12 and should be planned as their own work.

---

## 15. Lead review of round 2–5 captures and live verification

The lead auditor opened and inspected every capture in `captures-r2/` (31) and `captures-r3/` (20). Round 5 (`captures-r3/r5-*`) is a live harness session the lead drove: `--scenario slow-stream`, the controlled Git fixture `~/.piframe-harness/ui-git-fixture/workspace`, light theme, 1584×991. All destructive dialogs were cancelled with Escape. Afterwards `git status` on the fixture still showed both staged files, the session still existed, and the harness logs had no Flutter exceptions or overflow errors.

### 15.1 Findings confirmed by the captures

| Earlier finding | Capture evidence | Result |
|---|---|---|
| P1-11 Packages tab: unlabeled spinner | `r2-05`, `r2-06`: still a lone spinner after ~10 s, no text or timeout | Confirmed (fake-pi) |
| P1-10 Weak focus visibility | `r2-12`–`r2-19`: focus looks the same as hover (grey fill or round halo); `r2-19` shows no visible focus at all | Confirmed. See also 15.3-N1 |
| P1-1/P1-2 Git rows | `r2-08`: rows 56 px; at 1904 px the Git pane is ~380 px and still truncates paths | Confirmed |
| P2-10 Git groups collapsed leave an empty pane | `r2-03`, `r2-26`–`r2-30`, `r5-01` | Confirmed |
| P2-5 Context-irrelevant palette commands | `r2-20`: "Interrompi agente (Esc)" offered on a completed session | Confirmed |
| P2-3 Escape does not close Settings | `r5-06`: after Escape, Settings is still open | Confirmed live |
| P2-13 New-session dialog busy state | `r2-31`: idle dialog (Crea disabled), yet the welcome button behind it already reads "Creazione…" | Confirmed |
| P1-7 Streaming → settled layout shift | `r5-02`/`r5-03` (no role header, no timer) → `r5-07` (header + timer appear) | Confirmed live |
| §6.7 item 2 Composer hidden while streaming | `r5-02`, `r5-08`: a **focused** composer stays open and shows "Aggiungi istruzioni…" with stop/steer/follow-up controls | **Narrowed**: collapse affects only the unfocused composer (`40`). P1-6 stays, but at reduced scope |
| §6.3 "placeholder looks like a value" | `r2-21`: with an active session the field is **prefilled** with the session cwd | **Narrowed**: the issue applies only to the first-run case (no session) |

### 15.2 Live verification of round 3 changes

| Check | Evidence | Result |
|---|---|---|
| Reduced-motion toggle exists, applies and persists | `r5-04`, `r5-05`, `r5-06`; earlier `motion-toggle-on/off` | PASS |
| Composer ring moves in normal motion | `r5-02` vs `r5-03` (taken ~1 s apart while streaming): ring absent in one frame, beam visible at top-right in the other | PASS |
| Composer ring is static under reduced motion | `r5-08` vs `r5-09`: identical static accent ring in both frames | PASS |
| P0 fix | Not reproducible with fake-pi (no scenario sends a provider error with an empty reply) | Covered by the 3 reducer tests (§14.1) only |
| Working-dot and subagent pulse under reduced motion | No scenario produced a running subagent; the session row dot showed no run state in a frame | **[NV]**: code-gated (§14.2) and unit-tested only |

Under the light theme in normal motion the ring is faint and the resting composer border is nearly invisible against the white pane (`r5-02`). The composer edge relies on a ~1.4:1 border (§5.1).

### 15.3 New findings from the captures

| ID | Priority | Finding | Evidence | Impact | Cx |
|---|---|---|---|---|---|
| N1 | **P1** | **Tab order jumps across panes.** From the composer, the first Tab goes to the *last* Git row, then its actions, then the sessions footer (Impostazioni, search), then the *last* file-tree row. The order is neither visual nor pane-by-pane. | `r2-12`–`r2-19` | Keyboard users cannot predict where focus goes; with no visible ring (P1-10) they get lost. | M (`FocusTraversalGroup` per pane, ordered) |
| N2 | **P1** | **Discard dialog: "Annulla" next to "Annulla modifiche".** In Italian both mean cancel/undo, so the safe button and the destructive button share a verb. The destructive button uses the accent, not danger, colour. The consequence sentence sits far below the diff, next to the buttons. | `r5-11` | High risk of an accidental discard of work that cannot be recovered. The delete-session dialog (`r5-14`) already gets this right with a danger-red "Elimina" and the consequence in the body. | S: rename to "Scarta modifiche" with the danger style; keep "Annulla" for cancel |
| N3 | P2 | **Destructive styling inconsistent across dialogs.** Delete session uses the danger fill (`r5-14`); Git discard uses the accent fill (`r5-11`); the extension confirm uses the accent (`r2-27`). | `r5-11`, `r5-14`, `r2-27` | Users lose the red-means-irreversible cue. | S |
| N4 | P2 | **Command palette stays open after it launches a dialog.** Choosing "Crea nuova sessione" leaves the palette visible behind the New-session dialog. | `r2-21` | Stacked overlays; after cancelling, the palette is still there. | S |
| N5 | P2 | **Git group header overlaps the summary line when the list scrolls.** "MODIFICHE PREPARATE (STAGED)" renders half-hidden under "207 file +74626 −9", with the text overlapping. | `r2-12`–`r2-24` (dark and light) | Visual defect; the group header becomes unreadable. | S (clip the scroll area below the summary) |
| N6 | P2 | **The Git list already uses the right pattern elsewhere.** The @-mention menu shows the **name** bold, then the muted path, then the size (`r2-23`). The Git rows truncate the path from the start instead. | `r2-23` vs `r2-08` | An internal precedent for the P1-1 fix: reuse the @-menu row layout. | S |
| N7 | P2 | **Slash menu copy is English inside the Italian UI.** Command descriptions ("Open settings menu") and the source label "builtin" are English. DESIGN §08 names the source labels `Pi`/`estensione`/`prompt`/`skill`. | `r2-22` | Mixed language; contradicts the documented naming rule. | S |
| N8 | P2 | **Settings back button has no tooltip or semantic label**, and no key. Harness tree shows an unlabeled `IconButton`. | `r5-06` tree output | Screen readers announce an unnamed button; it is not testable by key. | S |
| N9 | P2 | **Crash recovery composer shows a stop button for a stopped worker.** After "Worker arrestato", the composer still shows a red stop icon next to the steer and refresh icons. All three are unlabeled. The banner wraps mid-word ("re-\ninviato"). | `r2-28` | Ambiguous actions in the recovery path; one of them does nothing. | S |
| N10 | P3 | **The "read" tool icon is drawn in the danger red.** Tool rows for successful reads use a red file glyph. | `r2-29`, `36` | Reads as an error on success rows. | S |
| N11 | P3 | **New sessions are named "Nuova Sessione"** (Title Case, unlike "Nuova sessione" on the welcome), or a timestamp. Several sessions in one repository become indistinguishable. | `r2-26`–`r2-30`, `r5-12` | Weakens the find/switch critical flow (§6.4 item 5). | M |
| N12 | P3 | **Session row shows no time or run state**, and is 56 px tall. | `r5-12` | Less scannable than needed for find/switch. | S |
| N13 | P3 | **Session menu mixes scopes.** "Rimuovi repository dal riquadro" (repository level) sits in the per-session menu. The menu divider is a heavy dark rule. | `r5-13` | Users may think the action only affects the session. | S |
| N14 | P3 | **Tooltips repeat what is already visible.** Hovering a fully visible file name shows the same name in a tooltip, while truncated Git paths get none. | `r2-07`, `r2-08` | Tooltips appear where they add nothing and are missing where they would help. | S |
| N15 | P3 | **Settings tab hover is a square grey block**, against the rounded surface grammar. | `r2-06` | Minor inconsistency. | S |

### 15.4 Roadmap impact
- Add **N1** and **N2** to the P1 list in §12. N2 is a one-line copy and style change with a large safety gain, so do it first.
- Fold N3 into P2-1 (semantic colour), N5 and N6 into P1-1/P1-2 (Git rows), N7 into P2-2 (language), N8 into P1-10 (keyboard and accessibility), and N9 into §6.7.
- §8's viewport observations (1280: chat + one companion at ~720/526 px; 1424: still the medium layout; 1904: full triptych) support P2-19. A wider triptych at the default window size remains a product decision.

### 15.5 Completion status of the audit
- All documented routes and significant screens: reviewed (§6). Review Changes is the only screen not seen rendered (no fixture can reach it).
- All available screenshots: inspected by the lead. Further mobile-web captures are out of scope by maintainer decision.
- Navigation, design system, desktop, interaction, accessibility and motion: assessed, with live verification where the harness could reach the state.
- Remaining verification gaps: Review Changes, the working-dot and subagent pulse under reduced motion, text scaling, and the P0 fix against a real provider error. All four are listed above as **[NV]**. §16 closes the first three.

## 16. Round 6: full fake-pi and harness coverage

fake-pi and the harness were extended so every feature can be reached offline: 30 scenarios with per-prompt switching, seeded fixtures (Git repositories, sessions, pinned session, MCP), the Pi package CLI and a fake npm, and the harness commands `media`, `drag`, `rightClick`, `tapAt`, `doubleTap` and `longPress`. See `tools/harness/README.md`. Evidence: `captures-r6/`.

### 16.1 Gaps closed live
| Gap | Evidence | Result |
|---|---|---|
| P0 fix with a provider error | `v-02-provider-error`, `v-t-batch1` | PASS. The user message is marked failed with the 429 text and a retry button. An error after a partial reply shows "Risposta interrotta da un errore: …" under the reply. |
| Review Changes | `v-03-edit-files` → `v-04-review-changes` | PASS. The pane lists the 4 changed files with +/− counts. |
| Subagents, workflow, task notifications | `v-05-subagents-a/b`, `v-06-media` | PASS |
| Text scaling 1.4× | `v-06-media` | Reachable. See 16.2 R4. |
| Packages (list, update available, pinned, git source), Agents, MCP | `v-p-packages`, `v-p-agents`, `v-p-mcp` | PASS. The Packages tab no longer hangs. |
| Question preview, input, editor, session tree, todos, extension status, slash menu, rich content | `v-q-preview`, `v-d-ui-*`, `v-tree`, `v-s-*`, `v-status`, `v-d-slash2` | PASS |
| Escape closes Settings; Settings back button tooltip/key | `v-p-esc` | PASS (fixed in round 6) |
| Pane divider drag | `v-07-drag` | PASS |

Still **[NV]**: the working-dot and subagent pulse loops under reduced motion. They are reachable now, but the 8 s run ended before two comparison frames were taken. The history-paging banner of the 150-message session was not seen after scrolling.

### 16.2 New defects the extended harness exposed
| ID | Priority | Finding | Evidence |
|---|---|---|---|
| R1 | **P1** | **RenderFlex overflows at narrow chat widths.** With the Agents sidecar open, the chat pane narrows to about 300 px. The Todo panel header, the task-notification card and the assistant header (timer + copy) all overflow (debug stripe; clipped in release). | `v-s-todos`, `v-s-ui-status-widgets`, `v-07-drag` |
| R2 | **P1** | **The Agents sidecar squeezes the chat.** It takes about 360 px, so the session title and status chips truncate and the composer chips overlap (the model chip runs under the expand icon). | `v-05-subagents-a` |
| R3 | P2 | **The startup update banner covers the composer controls** (model, thinking, send) until it is dismissed. | `v-02-provider-error`, `v-03-edit-files` |
| R4 | P2 | **Markdown tables render as raw pipes**, and the image block shows a broken-image placeholder for a valid PNG. | `v-s-rich-content` |
| R5 | P2 | **An aborted turn has no indicator.** The partial reply looks like a normal completed answer. | `v-t-batch1` |
| R6 | P2 | **The elapsed-time chip trusts the previous entry's timestamp.** A gap to a summary or custom entry with an old timestamp showed "944953012s". Real Pi data is unlikely to trigger this, but the chip should ignore non-message predecessors or cap absurd values. | `v-s-ui-status-widgets` (fixture since corrected) |
| R7 | P3 | **The session tree dialog is a flat list.** Branches are not visually nested, so the fork structure is hard to read. | `v-tree` |
| R8 | P3 | **Extension status text truncates** in the session header ("offline-check · CHECKING S…"). | `v-status` |
| R9 | P3 | **Agents tab model selects show "—"** with no models, although fake-pi returns two. Needs investigation (temporary RPC model query). | `v-p-agents` |

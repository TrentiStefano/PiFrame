# Local verification before a pull request

`ci.yml` checks every pull request, but the release workflow (`release.yml`, with its Windows and macOS installer builds) only starts after a merge into `main`: if it fails there, it has already used runner minutes (Windows ×2, macOS ×10) and `main` is broken. These two commands run the same steps **on your machine**, before the PR.

## Commands

```bash
pnpm run check             # inner loop: escape-hatch audit, doc link, agent map, design lint and design token checks, type checking, the Dart analysis under the diagnostics ratchet (+ the test files you pass)
pnpm run verify            # CI checks + release validation
pnpm run pr                # verify + push the branch + open the PR (gh pr create)
```

Options (they work for both commands; with `pnpm` they go after `--`):

| Option | Effect |
|---|---|
| `--release` | adds `flutter build web` and the `flutter build` for your desktop OS, as in the installer build job |
| `--e2e` | adds the emulated-iPhone test of the remote web app (`tools/remote-e2e`; it needs Playwright in `~/.pf-e2e`, see its README) |
| `--force` | ignores the cached result and runs everything again |
| `--no-merge` | checks only `HEAD`, without merging `origin/main` |
| `--keep` | keeps the temporary worktree (for debugging) |
| `--verbose` | prints the output of every step instead of saving it and printing only errors |

`pnpm run pr` also takes `gh pr create` arguments, for example `pnpm run pr -- --title "fix: ..." --body-file body.md`. A body is required: `--body` or `--body-file`, filled in from `.github/pull_request_template.md`. Without one, `pnpm run pr` refuses (the commits are no longer used to fill it). The body is checked before anything is pushed (see [PR body check](#pr-body-check)).

## The inner loop: `check`

`pnpm run check` is the fast tier to run after every small change. It runs the `check` tier of the shared step list in the **current working tree**, uncommitted changes included: no `pnpm install`, no worktree, no merge with `origin/main`, no cache. It assumes `pnpm run setup` has been run once.

`check` never installs dependencies. After a dependency change (one you made, or one you pulled, such as the `@google/design.md` and `yaml` packages the design checks use), run `pnpm install` first; otherwise the step that needs the missing package fails with `Cannot find package`.

1. the escape-hatch audit (see [below](#escape-hatch-ratchet)), the doc link check (see [below](#doc-link-check)), the named-timer check (see [below](#named-timers)), the agent map check (see [below](#agent-map-check)), the import-boundary check (see [below](#import-boundaries)), the design lint (see [below](#design-lint)) and the design token check (see [below](#design-token-check))
2. `pnpm -r run build` (agentd and the e2e tests type-check against the other packages' built `.d.ts`; a fresh or stale `dist/` would give false errors)
3. the TypeScript and ESLint ratchet (`tsc --noEmit` for every TypeScript package and type-aware ESLint, see [TypeScript ratchet](#typescript-ratchet)), after the build
4. `node tools/scripts/sync-changelog.mjs` (what `pnpm run sync:changelog` runs): generates the in-app changelog, which the app's `pubspec.yaml` lists, so the Dart analysis and the Flutter tests find it
5. Dart analysis (`dart analyze --format=machine`) on `pi_frame_protocol`, `pi_frame_theme` and `pi_frame`, compared with the diagnostics ratchet
6. each test file passed as an argument, routed by its path:
   - `*_test.dart` inside one of the Flutter projects → `flutter test <path>` in that project
   - `*.test.mjs`, `*.test.cjs`, `*.test.js` → `node --test <path>` from the repository root
   - `<package>/src/**/*.test.ts` (also `.mts`, `.cts`, `.tsx`) → `node --test` on its compiled copy `<package>/dist/**/*.test.js` (`.mjs`, `.cjs`), which step 2 refreshes: `apps/agentd/src/pi/test/jsonlFramer.test.ts` runs `apps/agentd/dist/pi/test/jsonlFramer.test.js`. A TypeScript test outside a `src/` folder fails; pass its compiled file instead.

Any other path fails before anything runs, with a message naming the supported kinds. Paths may be relative to the folder you run the command from.

```text
# (each step's own output omitted)
$ pnpm run check -- apps/pi_frame/test/changelog_test.dart apps/agentd/src/pi/test/PiEventAdapter.test.ts tools/guardrails/test/steps.test.mjs
[1/13] Escape-hatch audit (baseline ratchet) ... ok (1.8s)
[2/13] Doc links (relative links and anchors resolve) ... ok (0.3s)
[3/13] AGENTS.md map check (length, paths, scripts) ... ok (0.2s)
[4/13] Import boundaries (layers, daemon table, baseline) ... ok (0.4s)
[5/13] DESIGN.md lint (@google/design.md) ... ok (0.4s)
[6/13] DESIGN.md tokens match the theme ... ok (0.2s)
[7/13] Build TypeScript packages ... ok (9.4s)
[8/13] TypeScript and ESLint ratchet ... ok (4.8s)
[9/13] Generate the in-app changelog ... ok (0.1s)
[10/13] Flutter analyze (all projects) ... ok (30.4s)
[11/13] Flutter test apps/pi_frame/test/changelog_test.dart ... ok (11.4s)
[12/13] Node test apps/agentd/dist/pi/test/PiEventAdapter.test.js (compiled from apps/agentd/src/pi/test/PiEventAdapter.test.ts) ... ok (0.2s)
[13/13] Node test tools/guardrails/test/steps.test.mjs ... ok (0.3s)
✔ check: all 13 steps passed in 59.8s.
```

The `check` tier is local only: `ci.yml` follows the `ci` tier, so adding a step to `check` does not change the workflow. `check` passing does not mean "ready for a PR"; only `verify` does.

## What it checks

`verify` checks the current **commit** (`HEAD`) merged with `origin/main`, in a temporary worktree next to the repository (`<repo>-verify-<pid>`, not in the system temp folder: some tests fail when the repository is there). It checks what `main` will be after the merge, not only your branch. If the merge with `origin/main` has conflicts, it stops and tells you. Before it starts, it deletes the `<repo>-verify-<pid>` folders that earlier runs left next to this checkout or the main worktree. It deletes only folders with a positive sign that they are verify worktrees of this repository (registered in git, or whose `.git` file points into this repository, or that still hold this repository's root files), whose run is no longer alive, and never a folder without any such sign; the decision is `selectStaleVerifyWorktrees` in `tools/guardrails/src/verify-worktrees.mjs`, and the folder reading and long-path deletion are in `tools/scripts/verify-folders.mjs`. On Windows the deletion handles paths longer than 260 characters. At the end it fails, naming every verify folder of this run (or a stale one) still on disk; another live run's folder is not a leftover. The tests run in the verification worktree, so the clean-tree check is made there: a test that changes a tracked file fails `verify` and names the file.

The steps come from one shared step list, `tools/guardrails/src/steps.mjs`. `verify` runs its `verify` tier, and `.github/workflows/ci.yml` (which runs on every pull request and on pushes to `main`) runs its `ci` tier: the same steps, split into a Node and a Flutter job. A parity test in `tools/guardrails` fails when `ci.yml` drifts from the list, so to add or change a check, edit the step list first and then copy the YAML the test prints.

1. `pnpm install --frozen-lockfile`
2. TypeScript/Node formatting (Prettier `--check`)
3. the escape-hatch audit (see [below](#escape-hatch-ratchet)), the doc link check (see [below](#doc-link-check)), the agent map check (see [below](#agent-map-check)), the import-boundary check (see [below](#import-boundaries)), the design lint (see [below](#design-lint)) and the design token check (see [below](#design-token-check))
4. `node tools/recon/verify.ts`
5. PCP schema validation
6. `pnpm -r run build` (including the daemon bundle build)
7. the TypeScript and ESLint ratchet (see [TypeScript ratchet](#typescript-ratchet))
8. codegen parity (`tools/codegen/generate.js`: schema, TypeScript and Dart command/event types match)
9. `pnpm -r run test` (including the step-list and parity tests)
10. `pnpm run check:notices`
11. `check:agentd-bundle` and `smoke:agentd-bundle`
12. Windows release-name tests
13. Flutter dependencies (`tools/scripts/setup-flutter.js`; it also generates the in-app changelog)
14. `node tools/scripts/check-version-sync.mjs` (synchronized versions, and the in-app changelog in check mode)
15. Dart formatting (`dart format --set-exit-if-changed`)
16. Dart analysis (diagnostics ratchet) and `flutter test` (which first regenerates the in-app changelog) on `pi_frame_protocol`, `pi_frame_theme` and `pi_frame`
17. with `--release`: `flutter build web` and `flutter build <desktop>`
18. with `--e2e`: emulated-iPhone test

## Formatting

`pnpm run format` formats everything; `pnpm run format -- dart` or `-- ts` does one language, and `pnpm run format:check` only checks (what steps 2 and 15 run). Dart uses `dart format` with page width 120 (set in each Dart project's `analysis_options.yaml`, which includes the shared `packages/pi_frame_lints`); TypeScript and Node tooling (`apps/agentd`, `packages/pcp-*`, `test/e2e`, `tools`) use Prettier with `.prettierrc.json`. `tools/recon/reference/` holds verbatim upstream files and is excluded; `.prettierignore` also lists Markdown, YAML, JSON, the website and the Flutter app so an editor running Prettier agrees with the gate. Prettier uses `endOfLine: "auto"`: Windows checkouts (`core.autocrlf`) have CRLF files while git stores LF, so line endings are left to git. The Dart check covers each project's `lib/` and `test/` (the only Dart folders today); a new Dart folder such as `bin/` or `integration_test/` must be added to `tools/scripts/format.mjs`, and a new Dart project to `tools/scripts/flutter-projects.json`.

The one-time reformat commit is listed in `.git-blame-ignore-revs`: GitHub skips it in blame views automatically; locally run `git config blame.ignoreRevsFile .git-blame-ignore-revs` once. **Other branches** that existed before the reformat: run `pnpm run format` on them and commit before merging, and most conflicts disappear.

## In-app changelog

`apps/pi_frame/assets/CHANGELOG.md` (the post-update popup) is a generated copy of the root `CHANGELOG.md` and is not committed. `pnpm run sync:changelog` (`node tools/scripts/sync-changelog.mjs`) writes it; `pnpm run setup`, `run:app`, `run:app:dev`, every Flutter test path (`tools/scripts/test-flutter.js`, `pnpm run check -- <file>_test.dart`), the packaging scripts and the release workflow run it before Flutter. The version check (`pnpm run check:version`, step 14) only checks it: a missing or stale copy fails with the command that fixes it, and nothing is written. That check is for your local checkout, where a copy generated before you pulled a new release can be left on disk. In `verify` and CI the worktree is fresh and step 13 has just generated the copy, so there it cannot be stale. If `pnpm run check:version` fails on it, run `pnpm run sync:changelog` (or `pnpm run setup`). The decision logic is `syncChangelog` in `tools/guardrails`.

The full output is in `.git/verify-ci/last.log`. If a step fails, the script prints the last lines and stops: with `pnpm run pr`, nothing is pushed and no PR is opened.

## Agent guard

Agents use the maintainer's `gh` login, so GitHub cannot tell an agent's label click from the human's. A shared guard (`guardCommand` in `tools/guardrails`) blocks any `gh` invocation that mentions `human-approved` (any flag order or quoting, inside `sh -c`/`bash -c`, PowerShell and `gh api`) and `gh label create|edit|delete`. Everything else is allowed, including other labels, `--add-sub-issue`, `--add-blocked-by` and the dependency/sub-issue `gh api` calls in `docs/agents/issue-tracker.md`. A `gh` command that only mentions the label in prose (an issue body or comment) is blocked too: write the text to a file and pass `--body-file`.

Each agent enforces it with its own mechanism, all committed:

- **Claude Code**: `.claude/settings.json` has `permissions.deny` rules for the common forms (Bash and PowerShell tools) and a `PreToolUse` hook, `.claude/hooks/guard-command.mjs`, that calls the guard for every Bash/PowerShell command. Try it: `echo '{"tool_name":"Bash","tool_input":{"command":"gh pr edit 999999 --add-label human-approved"}}' | node .claude/hooks/guard-command.mjs`.
- **pi**: `.pi/extensions/guard-command.ts` blocks `bash` and `powershell` tool calls the guard rejects. pi loads project extensions only after you trust the project.
- **Codex**: `.codex/rules/guard.rules` forbids `gh label` and asks before `gh pr edit`, `gh issue edit` and `gh api` (Codex rules match exact prefixes only, so they cannot call the guard). Codex loads them only after you trust the project; check with `codex execpolicy check --pretty --rules .codex/rules/guard.rules -- gh label delete wip`.

Git tracks `.claude/` except `skills/` (installer symlinks), `worktrees/` and `settings.local.json`, and `.pi/` only for `extensions/`. The guard is a speed bump, not a security boundary: an agent determined to call the GitHub API another way still can, which is why approval also expires on the next push and the human reviews the PR.

## Cache

A passing result is valid for the same content (tree hash), the same base (`origin/main`) and the same level. Running it again without changes is instant. After a new commit, or when `origin/main` has moved, it runs again.

## Prerequisites

- A **clean** working tree: `verify` checks what you committed, so commit first.
- `git`, `pnpm`, Node and Flutter (the workflow versions are in `.github/workflows/release.yml`; the script warns when yours differ).
- For `pnpm run pr`: the GitHub CLI (`gh`), signed in with `gh auth login`.

## Limits

- It runs on one operating system only: the Linux (`.deb`, screenshots with `xvfb`) and macOS (`.dmg`) jobs of the workflows are not reproduced, and path or letter-case differences on Linux can slip through.
- Plain test runs never write tracked captures: the capture tests write to a temporary folder that they delete when the test file finishes. To refresh the tracked design evidence and website captures on purpose, run `pnpm run capture:evidence`, which sets the capture flags for all four capture tests; review the result with `git status` before committing.
- It is a local check and can be bypassed. It does not replace the GitHub workflows; it protects them from avoidable failures.

## Build and release problems

- **`EBUSY: resource busy or locked, symlink` on Windows** (`pnpm install` or `pnpm build:all`, often followed by `'tsc' is not recognized`): a running PiFrame, daemon or terminal holds the package folders. Stop them (`Stop-Process -Name "pi-agentd","PiFrame" -ErrorAction SilentlyContinue`) and run `pnpm install` again.
- **`pnpm run package:windows` cannot copy `node.exe` or `PiFrame.exe`**: a PiFrame or daemon started from `apps/pi_frame/build/windows/x64/runner/Release/` still runs. The script stops processes inside that folder and retries; close any it misses. After a successful Flutter build, repackage without rebuilding: `powershell -ExecutionPolicy Bypass -File tools/scripts/package-windows-installer.ps1 -SkipBuild`.
- **Linux build: `webkit2gtk-4.1` or `libnotify` not found**: install the development packages, `sudo apt-get install libwebkit2gtk-4.1-dev libnotify-dev`. The release workflow does the same.
- **Web build: `Dart library 'dart:ffi' is not available on this platform`**: code that uses `dart:ffi` is reachable from `main.dart` without a conditional import (`stub.dart if (dart.library.ffi) 'real.dart'`). `web_ffi_import_test.dart` catches it; `--release` runs the web build itself.
- **Daemon unreachable after building PiFrame from source**: you built `PiFrame.exe` yourself (for example `flutter build windows --release`) and the app cannot connect to the daemon, the sessions list shows `TimeoutException after 0:00:08.000000`, or **Settings → Daemon → Restart daemon** keeps failing. A Flutter build does not rebuild the daemon, and it does not stop a daemon that is already running; when the daemon bundle next to `PiFrame.exe` is older than the app, the app stops it because of the version difference and starts the same old bundle again. Rebuild the daemon first, then the app (`pnpm build:agentd`; the build copies `apps/agentd/dist/pi-agentd.cjs` next to `PiFrame.exe`; copy `node.exe` there too if it is missing). Let running Pi workers finish, then use **Settings → Daemon → Restart daemon**. If the restart still fails, close PiFrame, end the old daemon (the `pi-agentd` process in Task Manager, or the process id in `~/.piframe/runtime/daemon.json`: `Stop-Process -Id (Get-Content "$HOME\.piframe\runtime\daemon.json" | ConvertFrom-Json).pid`), and start PiFrame again.
- **GitHub Pages returns 404**: in **Repository Settings → Pages**, set **Build and deployment → Source** to **GitHub Actions**.
- **Rebuilding an old release**: **Actions → Release → Run workflow** with an older tag uses the current workflow but that tag's packaging scripts, so packaging fixes made later are not in the rebuilt installers. Cut a new release instead.
- **Context-limit smoke test**: after building the daemon, `node tools/scripts/smoke-context-policy.mjs` runs real Pi against a local HTTP model in temporary folders, with no calls to paid providers.

## Example

```text
$ pnpm run verify
Merged origin/main (2 commit(s)) into the verification worktree.
[1/13] Install dependencies (frozen lockfile) ... ok (4.1s)
...
[13/13] Flutter tests (all projects) ... ok (92.3s)
✔ All 13 steps passed in 6.8 min.  Result cached for this exact content (ci).
```

## Escape-hatch ratchet

`node tools/scripts/audit-escape-hatches.mjs` (in `check`, `verify` and CI) counts the ways code silences a check and compares them with the committed baseline `tools/guardrails/escape-hatch-baseline.json`. Any difference fails, so the numbers can only go down.

- **Patterns.** Dart: `// ignore:` and `// ignore_for_file:`. TypeScript and JavaScript: `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`, `eslint-disable`, `as any`, `: any` and `as unknown as`. Both: `coverage:ignore` (any form). Every occurrence counts, comments included; `as any` and `: any` only in a type position (followed by punctuation, `as` or the line end), so prose such as "two ways: any call" does not.
- **Packages.** `agentd` (`apps/agentd`), `pcp-ts`, `pcp-spec`, `pi_frame_protocol`, `pi_frame_theme` (`packages/*`), `pi_frame` (`apps/pi_frame`), `tools` (`tools/`) and `e2e` (`test/e2e`). Each is split into `lib` and `test`: a file is test code when it sits in a `test`, `tests` or `__tests__` folder of its package, or is named `*_test.dart`, `*.test.*` or `*.spec.*`. Files elsewhere in the repository are not audited, nor anything in `node_modules`, `dist`, `build`, `out`, `coverage` or `.dart_tool` folders. The audit's own source and tests (`tools/guardrails/*/escape-hatches*`) spell out every pattern and are skipped. So are the vendored upstream declaration files under `tools/recon/reference/`, which are kept as published.
- **Baseline.** Every package × `lib`/`test` × pattern is listed, zeros included, so a first hatch in a clean area fails too. It counts per package, not per file: moving a hatch between files of the same package passes.
- **A count went up**: the message names the files and lines with that pattern (files changed since the baseline was last committed first, marked `(changed)`: one of them holds the new hatch) and how to fix the root cause. Fix the code; do not raise the baseline. Raising it is a human's decision (the `human-approved` label on the pull request).
- **A count went down**: the message gives the exact edit, for example `"agentd" → "lib": change "as any": 44 to "as any": 43`. Make it in the same commit.

The logic is `auditEscapeHatches` in `tools/guardrails/src/escape-hatches.mjs` (pure, tested with in-memory fixtures in `tools/guardrails/test/escape-hatches.test.mjs`); the script only reads the files (tracked plus untracked, not ignored, as they are on disk) and the baseline.

## Diagnostics ratchet

`node tools/scripts/lint-flutter.mjs` (the gate step "Flutter analyze (all projects)", in `check`, `verify` and CI) runs `dart analyze --format=machine` in every Dart project and counts the diagnostics per tool × package × rule. It compares them with the committed baseline `tools/guardrails/diagnostics-baseline.json`, as the escape-hatch ratchet does: a difference fails.

- **Rules.** `packages/pi_frame_lints/lib/analysis_options.yaml` (included by the app and both Dart packages): strict casts, inference and raw types; `discarded_futures`, `unawaited_futures`, `avoid_dynamic_calls`, `always_declare_return_types`, `avoid_print`; page width 120; the platform folders excluded.
- **Every severity counts**: errors, warnings and infos. The step does not pass `--fatal-warnings`: the baseline holds today's warnings, so a new warning fails the ratchet instead. Each fix ticket lowers its counts to zero.
- **Absent entries count from zero**: a new rule or package with a diagnostic fails.
- **A count went up**: the message lists the diagnostics of that rule in the package (files changed on this branch first, at most ten, then `... and N more`) and the fix for the rule. Do not raise the baseline; a raise needs the `human-approved` label (see [Guardrail approval](#guardrail-approval)).
- **A count went down**: the message gives the exact edit to the baseline, made in the same commit.
- **The tool is part of the key** (`dart-analyze`, `tsc`, `eslint`). Each adapter passes only its own tools' slice of the shared baseline, so one step never judges another's counts.
- **Analyzer exit codes** 0 to 3 (no issues, infos, warnings, errors) are the data the ratchet judges; any other code fails the step.

The logic is `checkDiagnostics` and `parseDartAnalyzeMachine` in `tools/guardrails/src/diagnostics.mjs` (pure, tested on fixture text in `tools/guardrails/test/diagnostics-ratchet.test.mjs`); the adapter reads the analyzer output and the changed files.

## TypeScript ratchet

`node tools/scripts/lint-typescript.mjs` (the gate step "TypeScript and ESLint ratchet", in `check`, `verify` and CI; `pnpm run lint` runs it too) runs `tsc --noEmit -p tsconfig.json` in every package listed in `tools/scripts/typescript-projects.json` (`apps/agentd`, `packages/pcp-ts`, `test/e2e`, `tools/fake-pi`, `tools/fault-proxy`), then ESLint once over the packages' `src` folders. Both feed the diagnostics ratchet under the tool names `tsc` and `eslint`, with the baseline counts per package and rule.

- **Compiler flags.** `tsconfig.base.json` sets `strict` plus `noUnusedLocals`, `noUnusedParameters`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `noFallthroughCasesInSwitch`. Every package `tsconfig.json` extends it.
- **Build.** `pnpm -r run build` compiles each package with its `tsconfig.json`, the same strict flags as the checker, so a build fails on any strict error. There is no separate build config.
- **ESLint.** `eslint.config.mjs` (flat config, type-aware via `projectService`) enables exactly `no-floating-promises`, `no-misused-promises`, `await-thenable`, `switch-exhaustiveness-check` and `no-unnecessary-type-assertion`. `node:test`'s `test` and `describe` are declared safe for `no-floating-promises` (`allowForKnownSafeCalls`), since they return promises the runner awaits. `eslint` and `typescript-eslint` are pinned exactly in the root `package.json`.
- **Build first.** The checks read the other workspace packages' `dist/*.d.ts`, so the build step runs before this one, as it does in `check`, `verify` and CI.
- **Parsers.** `parseTscOutput` reads `path(line,col): error TSnnnn: message` lines (the rule is the code); `parseEslintJson` reads ESLint's `--format json` report (the rule is `ruleId`, `parse-error` when there is none, and the package is the one that contains the file). Both are pure and tested on fixtures in `tools/guardrails/test/typescript-ratchet.test.mjs`.

## Doc link check

`node tools/scripts/check-doc-links.mjs` (in `check`, `verify` and CI) fails on any broken relative link in every Markdown file under `docs/`, every `README.md` (at any depth), and `AGENTS.md`, `GLOSSARY.md` and `DESIGN.md` at the root, so moving or deleting a document cannot leave a stale reference.

- **Links.** Inline Markdown links and images (`[text](target)`, `![alt](target)`, `<target>` and titles allowed), reference definitions (`[label]: target`) and HTML `src`/`href` attributes. A target is resolved against the linking file's folder (`/...` against the repository root) and must be a tracked file or folder (untracked, not ignored files on disk count too, as for the escape-hatch audit).
- **Anchors.** A `#heading` on a Markdown file (or a bare `#heading` in the same file) must match one of its headings, slugged as GitHub does (lower case, punctuation dropped, spaces as hyphens, duplicates as `-1`, `-2`), or an explicit `id`/`name` attribute. Any Markdown file in the repository can be linked to, `CHANGELOG.md` included. Anchors on other files (`foo.dart#L10`) are not checked.
- **Ignored.** External URLs (anything with a scheme, `https:`, `mailto:`, ..., or `//host`), fenced code blocks and inline code spans, so examples are not reported.
- **A link is broken**: the message names the file and line, the target and what is missing, and how to fix it; for a missing anchor it lists the anchors the target file has.

```text
✖ doc link check: 1 broken link(s):

- docs/install.md:60: the link "troubleshooting-gone.md" points at docs/troubleshooting-gone.md, which is not a tracked file or folder. To fix it, point the link at where that file is now (relative to the linking file), or remove the link if the file was deleted.
```

The logic is `checkDocLinks` in `tools/guardrails/src/doc-links.mjs` (pure, tested with in-memory fixtures in `tools/guardrails/test/doc-links.test.mjs`); the script only lists the files and reads the Markdown ones. Both are guarded paths (see below).

## Agent map check

`node tools/scripts/check-agent-map.mjs` (in `check`, `verify` and CI) keeps `AGENTS.md` a short, correct map. It fails when the file:

- is over 100 lines (the final newline does not count);
- names a path that matches no file or folder in the repository (tracked plus untracked, not ignored). Paths are the tokens in inline code spans and fenced code blocks that contain a `/` or end in a file extension, plus relative link targets (anchors dropped). They are read from the repository root; a glob without a folder (`*_test.dart`) matches a file name anywhere. URLs, home (`~/`) and absolute paths, slash commands, flags, `<placeholders>` and `@scoped/packages` are not paths;
- runs `pnpm run <script>` where the root `package.json` has no such script.

Each message names the line, for example ``AGENTS.md:11 names `scratch/release_ui_screenshots/*.png`, which matches no tracked file or folder. Fix the path or remove the mention.`` The logic is `checkAgentMap` in `tools/guardrails/src/agent-map.mjs` (pure, tested with in-memory fixtures in `tools/guardrails/test/agent-map.test.mjs`); the script only reads `AGENTS.md`, `git ls-files` and the root `package.json`.

## Import boundaries

`node tools/scripts/check-boundaries.mjs` (in `check`, `verify` and CI) enforces the layer rules on the sources as they are on disk (tracked plus untracked, not ignored). It reads Dart `import`/`export` lines and TypeScript `import`/`export ... from` and literal `import()`, and resolves relative imports and `package:pi_frame/` imports to the same file.

- **Flutter** (`apps/pi_frame/lib/`): `domain/` imports no `package:flutter/`, no `package:flutter_riverpod/` or `package:riverpod/`, no raw I/O and nothing from `data/`, `features/`, `ui/` or `app/`; `data/` imports nothing from `features/`, `ui/` or `app/`; `ui/` imports nothing from `features/` or `app/`, and from `data/` only the translation tables in `data/language/` (user-facing text is presentation, not I/O); `features/` and `ui/` use no raw I/O or platform plugins (`dart:io`, `dart:ffi`, `ffi`, `http`, `web_socket_channel`, `win32`, `url_launcher`, `file_selector`, `desktop_drop`, `window_manager`, `local_notifier`, `webview_win_floating`). A feature may import another feature and any `ui/` or `data/` file, but never `app/`: shared widgets live in `ui/`. `harness/` is imported only from `app/` and the entry points (`lib/main*.dart`).
- **Daemon** (`apps/agentd/src/`): a module imports only the modules its row in `daemonAllowedDependencies` names, and the module graph has no cycles.
- **Packages** (`packages/`) never import `apps/`.
- Test files (`*_test.dart`, `*.test.ts`, anything under a `test/` folder) are not checked.

The rules, the daemon table and the **baseline** are in `tools/guardrails/boundary.json`. The baseline lists each violation that exists today as `{ "file", "import" }`; a daemon cycle is listed by its loop (`remote -> server -> remote`). A baselined violation passes. Any other violation fails, with the file and line, the import, the rule and how to fix it:

```text
✖ import boundaries: 1 problem(s):

- [raw-io] apps/pi_frame/lib/features/boundary_probe.dart:1 imports 'dart:io' in features/, which must not use raw I/O or platform plugins. Move that call into a service in data/, read it in this file through a provider, and test the feature with a fake of the service (docs/pr-verification.md, "Import boundaries").
```

A baseline entry that matches no violation any more fails too, and names the entry to delete, so the baseline only shrinks. To fix a violation, move the I/O into a service in `data/`, read it through a provider and test the feature with a fake of that service. An exception needs the `human-approved` label (the config is a guarded path): add the `{ "file", "import" }` entry to `baseline` and say why in the PR; a new daemon edge goes into `daemonAllowedDependencies` and is recorded in `docs/adr/`.

The logic is `checkBoundaries` in `tools/guardrails/src/boundary.mjs` (pure, tested with in-memory fixtures in `tools/guardrails/test/boundary.test.mjs`); the script only reads the files and the config.

## Named timers

`node tools/scripts/check-timers.mjs` (in `check`, `verify` and CI) enforces that every timer in the Flutter app (`apps/pi_frame/lib/`) and the daemon (`apps/agentd/src/`) has a named reason. A timer call fails when its duration is a numeric literal, or arithmetic that contains one: `Timer(`, `Timer.periodic(` and `Future.delayed(` (the first argument, in Dart), and `setTimeout(` and `setInterval(` (the second argument, in TypeScript). A named constant or a variable passes. Test code (`*_test.dart`, `*.test.ts`, anything under a `test/` folder), comments, and identifiers that only contain a digit are not counted.

Name the delay with a constant next to its use, named for why the wait exists (for example `_copiedFeedbackDuration` or `PONG_TIMEOUT_MS`), and pass that name to the timer. There are no exceptions: a literal duration fails the gate.

The Dart design-literals ratchet (`apps/pi_frame/test/design_literals_lint_test.dart`) is separate and unchanged: a millisecond timer constant there still needs an entry in its `_allowedTimerConstants`, so a named Dart timer in seconds or hours passes both checks without one.

The logic is `checkTimers` in `tools/guardrails/src/timers.mjs` (pure, tested with in-memory sources in `tools/guardrails/test/timers.test.mjs`); the script only reads the files.

## Design lint

`node tools/scripts/lint-design.mjs` (in `check`, `verify` and CI) runs Google's DESIGN.md linter (`@google/design.md`, pinned in the root `package.json`) on `DESIGN.md`. The linter's own CLI fails on errors only; this step fails on **errors and warnings**, and prints info findings without failing.

- **What it checks.** That `DESIGN.md` follows the DESIGN.md format, by the pinned linter's rules: the YAML front matter (`colors`, `typography`, `rounded`, `spacing`, `components`) parses, token names, formats and nesting are valid and not duplicated, references such as `{colors.dark.primary}` resolve to a defined token, keys and section names are ones the format knows, and a component's text and background colors have enough contrast.
- **A finding fails**: the message gives the severity, the linter's text and the path it points at (a front-matter token or a section). Edit `DESIGN.md` there, then run `node tools/scripts/lint-design.mjs` again. Do not add a group the pinned linter rejects: the motion tokens are a table in the `## Motion` section, not front matter, because 0.4.0 warns on a front-matter `motion` group (`DESIGN.md` says so there). A failure prints `✖ design lint: <n> error(s) or warning(s) in DESIGN.md`, then one `- <severity>: <message> (<path>)` line per finding.

## Design token check

`node tools/scripts/check-design-tokens.mjs` (in `check`, `verify` and CI) fails when a token in `DESIGN.md` differs from what the app ships. The shipped theme is the source of truth: the theme files `themes/*.json` (not `theme.schema.json`) and the theme package constants in `packages/pi_frame_theme/lib/src/` (`theme_text.dart` for the type roles, `theme_motion.dart` for durations and curves, `theme_scale.dart` for spacing).

- **What it compares.** The `colors`, `typography`, `rounded` and `spacing` groups of the front matter, plus the motion tokens from the `## Motion` table. Values are compared after normalising case, spaces and units (`6.0px` = `6px`); a token that only references another (`{colors.dark.primary}`) is an alias and is skipped, and `components` is not compared.
- **A token differs**: the message names the token, both values and the file to edit, for example `colors.dark.primary: DESIGN.md has #5f9fc5, themes/piframe-dark.json has #ff0000. To fix it, set colors.dark.primary to #ff0000 in DESIGN.md's front matter (...)`. Edit `DESIGN.md` (its front matter, or the Motion table for `motion.*`) unless the theme itself should change, in which case edit the theme file named. A token only one side defines is reported too, with where to add or remove it.

The logic is `checkDesignTokens` in `tools/guardrails/src/design-tokens.mjs` (pure, tested with in-memory fixtures in `tools/guardrails/test/design-tokens.test.mjs`); the script only reads the files. The doc link, agent map and design token checks share the Markdown reading in `tools/guardrails/src/markdown.mjs`, and the adapters list the repository's files through `tools/scripts/repo-files.mjs`.

## Golden screens

`apps/pi_frame/test/golden_screens_test.dart` renders five screens (welcome, workspace with a transcript, the composer with the slash menu open, the composer with a staged command chip, settings) in light and dark at 1920×1032 logical pixels and device pixel ratio 1, with the bundled fonts and the English test fixtures, and compares each with a reference PNG in `apps/pi_frame/test/goldens/` (ten references). The tests carry the `golden` tag, which `apps/pi_frame/dart_test.yaml` declares, so a plain `flutter test` and `pnpm run test` skip them. On Windows the run must execute at least one golden test (`goldenRunFailure` in `tools/guardrails/src/golden-run.mjs`), so a missing tag cannot pass silently.

- **Windows only.** Elsewhere `tools/scripts/goldens.mjs` prints why it did not run and exits 0.
- **`verify` only.** The golden step is the one documented verify-only step (`VERIFY_ONLY_STEPS` in `tools/guardrails/src/steps.mjs`): `ci.yml` and `pnpm run check` never run it, and the CI parity test asserts that `verify` is the `ci` tier plus exactly that step.
- **A mismatch fails the step** and the failure names the screen (for example `workspace (dark)`) and `pnpm run goldens:update`. The expected, actual and diff images stay in `apps/pi_frame/test/failures/` (git-ignored) until the next golden run clears that folder.
- **An intended change:** run `pnpm run goldens:update` and review the regenerated PNGs in the PR. The reference folder is a guarded path, so it needs the `human-approved` label like any other guardrail.

## Guardrail status

`pnpm run guardrails:status` (`node tools/scripts/guardrails-status.mjs`) prints the progress toward zero of the three committed baselines: the escape-hatch counts, the import-boundary baseline entries and the diagnostics counts, in total and per package (the audited package names, such as `agentd` or `pi_frame`). A package is `done` when all three count zero there, and the report says `All clear` when every baseline is zero. It is a report, not a gate step: it always exits 0, and it is not in the step list, so `check`, `verify` and CI do not run it. The logic is `guardrailsStatus` in `tools/guardrails/src/status.mjs` (pure, tested in `tools/guardrails/test/status.test.mjs`); the script only reads the three baseline files.

## Guardrail approval

`.github/workflows/guardrails-approval.yml` runs on every pull-request event (`opened`, `synchronize`, `reopened`, `labeled`, `unlabeled`). It is a separate workflow, not a `ci.yml` job, because `ci.yml`'s jobs must equal the step list's `ci` tier. It fails while the PR changes a guardrail without a current `human-approved` label:

- **A raised baseline number**: any count in `tools/guardrails/escape-hatch-baseline.json` that is higher on the PR head than at its merge base. Lowering is free.
- **A guarded path changed**, in either direction: every `analysis_options.yaml`, `tsconfig*.json`, `.prettierrc.json` and `.prettierignore`, any ESLint config (`.eslintrc*`, `.eslintignore`, `eslint.config.*`), `tools/guardrails/**` (except the two baseline files, see above), `tools/codegen/**`, **every script a gate step runs** (derived from the step list, all tiers: for example `tools/scripts/format.mjs`, `audit-escape-hatches.mjs`, `check-doc-links.mjs`, `check-agent-map.mjs`, `lint-design.mjs`, `check-design-tokens.mjs`, `lint-flutter.mjs`, `test-flutter.js`, `setup-flutter.js`, `check-version-sync.mjs`, `sync-changelog.mjs`, `tools/recon/verify.ts`, `tools/remote-e2e/remote-iphone-e2e.mjs`), the gate runners `tools/scripts/verify-ci.mjs` and `tools/scripts/check.mjs`, the adapters' file listing `tools/scripts/repo-files.mjs`, `tools/scripts/flutter-projects.json`, `tools/scripts/typescript-projects.json`, `tsconfig.base.json` and `tsconfig.build.base.json` (every `tsconfig*.json`), `eslint.config.mjs`, `tools/scripts/guardrails-approval.mjs`, every `package.json` (the root one and each workspace package's: the `build`, `lint` and `test` scripts and the Prettier pin live there) and `pnpm-workspace.yaml`, `.github/workflows/**`, the golden reference images `apps/pi_frame/test/goldens/*.png`, the golden screens test `apps/pi_frame/test/golden_screens_test.dart` and its runner `tools/scripts/goldens.mjs`, and the agent guards: `.claude/settings.json`, `.claude/hooks/**`, `.pi/extensions/**`, `.codex/rules/**`, and the agents' map `AGENTS.md`.

When approval is needed, the job posts **one** comment (found again by a hidden `<!-- guardrails-approval -->` marker and edited, never duplicated) listing each reason, for example ``agentd lib `as any` 44 → 45`` or ``CI workflow changed: `.github/workflows/ci.yml` ``. To approve, review the PR and add the label in the GitHub UI: the `labeled` event re-runs the job, which turns green and updates the comment; no push is needed. A PR that needs nothing passes silently, without a comment (if an earlier commit needed approval and no longer does, the existing comment says so).

**Staleness.** An approval counts only if the label was added after the latest push. Commit dates are written by whoever commits, so they are never used. The push time is one GitHub records: the creation time of the run itself when a push triggered it (`opened`, `synchronize`, `reopened`), otherwise the creation time of the newest `ci.yml` pull-request run for the head commit (`ci.yml` runs on exactly those events). On a push after approval the job fails, says in the comment that the approval is stale, and removes the label, so approving again is one click. If no push time can be found, any label counts as stale.

**Trust.** The job checks out the PR's **base** commit and runs the approval script from there; the PR head is fetched as data (its baseline file and changed paths) and never executed, so a PR cannot change the logic that judges it. The exception is bootstrap: while the base branch has no approval script, the PR's copy runs. The workflow file itself still comes from the PR (a `pull_request` workflow always does), so review any change to it by eye. Fork PRs get a read-only token: the verdict still holds, only the comment and the label removal are skipped. The token has `contents: read`, `actions: read` (the run times) and `pull-requests: write` (the comment and the label), and the job uses no secrets.

Try it locally (no GitHub access, so no labels: prints the verdict and the comment it would post):

```bash
node tools/scripts/guardrails-approval.mjs --base origin/main --head HEAD
```

The logic is `approvalStatus` in `tools/guardrails/src/approval.mjs` (pure, tested in `tools/guardrails/test/approval.test.mjs`); the script only reads git and GitHub and writes the comment. To make the check blocking, mark `Guardrail approval` as a required status check in the branch protection settings (a manual repository setting).

## PR body check

Every pull request body has the review shape of `.github/pull_request_template.md`: a `## Closes` section that links the issue or spec (`#81`, or an issue URL); `## Summary` and `## Evidence` of at least four words each; `## Merge Danger` with `**Door:**` exactly `one-way` or `two-way` (an explanation may follow) and `**Blast Radius:**` one word or a short phrase, never a single character; and `## Guardrail changes` that says `none` or is a sentence of at least four words. A body is refused when it still has the template's placeholder hints (`<one-way or two-way>`, `<one word>`) or a line that starts with a leftover `TODO:`, `TBD:` or `FIXME:` marker; a word such as TODO inside a sentence is content. HTML comments (the template's hints) are not content. Screenshots are not required.

The logic is `checkPrBody` in `tools/guardrails/src/pr-body.mjs` (pure, tested in `tools/guardrails/test/pr-body.test.mjs`, one case per rule). Two callers use it:

- **`pnpm run pr`** checks the body given with `--body` or `--body-file` before it pushes or calls `gh`, and names each missing part. It fails without a body at all. Try it without creating anything (it stops at the body check):

  ```bash
  node tools/scripts/open-pr.mjs --title "fix: x" --body "## Summary"
  ```

- **`.github/workflows/pr-body.yml`** runs `node tools/scripts/check-pr-body.mjs --pr <number>` on `opened`, `edited`, `synchronize` and `reopened`. It reads the body with the default token (`gh pr view`, `pull-requests: read`) and fails while the body is incomplete. It is a separate workflow, not a `ci.yml` job, for the same reason as the approval workflow. To check a body on disk: `node tools/scripts/check-pr-body.mjs --file body.md`.

The template, the check, the adapter (`tools/scripts/check-pr-body.mjs`) and the workflow are guarded paths: changing them needs the approval label described in [Guardrail approval](#guardrail-approval).

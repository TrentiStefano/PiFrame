# Local verification before a pull request

`ci.yml` checks every pull request, but the release workflow (`release.yml`, with its Windows and macOS installer builds) only starts after a merge into `main`: if it fails there, it has already used runner minutes (Windows ×2, macOS ×10) and `main` is broken. These two commands run the same steps **on your machine**, before the PR.

## Commands

```bash
pnpm run check             # inner loop: escape-hatch audit, type checking, flutter analyze (+ the test files you pass)
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

`pnpm run pr` also takes `gh pr create` arguments, for example `pnpm run pr -- --title "fix: ..." --body "..."`. Without a title and body it uses `--fill` (from the commits).

## The inner loop: `check`

`pnpm run check` is the fast tier to run after every small change. It runs the `check` tier of the shared step list in the **current working tree**, uncommitted changes included: no `pnpm install`, no worktree, no merge with `origin/main`, no cache. It assumes `pnpm run setup` has been run once.

1. the escape-hatch audit (see [below](#escape-hatch-ratchet))
2. `pnpm -r run build` (agentd and the e2e tests type-check against the other packages' built `.d.ts`; a fresh or stale `dist/` would give false errors)
3. `pnpm -r run lint` (`tsc --noEmit` for every TypeScript package)
4. `flutter analyze` on `pi_frame_protocol`, `pi_frame_theme` and `pi_frame`
5. each test file passed as an argument, routed by its path:
   - `*_test.dart` inside one of the Flutter projects → `flutter test <path>` in that project
   - `*.test.mjs`, `*.test.cjs`, `*.test.js` → `node --test <path>` from the repository root. TypeScript tests run from their build output (for example `apps/agentd/dist/pi/test/jsonlFramer.test.js`), which step 2 refreshes.

Any other path fails before anything runs, with a message naming the supported kinds. Paths may be relative to the folder you run the command from.

```text
# (each step's own output omitted)
$ pnpm run check -- apps/pi_frame/test/agents_config_model_test.dart tools/guardrails/test/steps.test.mjs
[1/6] Escape-hatch audit (baseline ratchet) ... ok (0.4s)
[2/6] Build TypeScript packages ... ok (9.5s)
[3/6] TypeScript lint (tsc --noEmit) ... ok (6.6s)
[4/6] Flutter analyze (all projects) ... ok (39.9s)
[5/6] Flutter test apps/pi_frame/test/agents_config_model_test.dart ... ok (17.7s)
[6/6] Node test tools/guardrails/test/steps.test.mjs ... ok (0.5s)
✔ check: all 6 steps passed in 74.6s.
```

The `check` tier is local only: `ci.yml` follows the `ci` tier, so adding a step to `check` does not change the workflow. `check` passing does not mean "ready for a PR"; only `verify` does.

## What it checks

`verify` checks the current **commit** (`HEAD`) merged with `origin/main`, in a temporary worktree next to the repository (`<repo>-verify-<pid>`, not in the system temp folder: some tests fail when the repository is there). It checks what `main` will be after the merge, not only your branch. If the merge with `origin/main` has conflicts, it stops and tells you.

The steps come from one shared step list, `tools/guardrails/src/steps.mjs`. `verify` runs its `verify` tier, and `.github/workflows/ci.yml` (which runs on every pull request and on pushes to `main`) runs its `ci` tier: the same steps, split into a Node and a Flutter job. A parity test in `tools/guardrails` fails when `ci.yml` drifts from the list, so to add or change a check, edit the step list first and then copy the YAML the test prints.

1. `pnpm install --frozen-lockfile`
2. TypeScript/Node formatting (Prettier `--check`)
3. the escape-hatch audit (see [below](#escape-hatch-ratchet))
4. `node tools/recon/verify.ts`
5. PCP schema validation
6. `pnpm -r run build` (including the daemon bundle build)
7. `pnpm -r run lint` (`tsc --noEmit` for every TypeScript package)
8. codegen parity (`tools/codegen/generate.js`: schema, TypeScript and Dart command/event types match)
9. `pnpm -r run test` (including the step-list and parity tests)
10. `pnpm run check:notices`
11. `check:agentd-bundle` and `smoke:agentd-bundle`
12. Windows release-name tests
13. Flutter dependencies (`tools/scripts/setup-flutter.js`; it also generates the in-app changelog)
14. `node tools/scripts/check-version-sync.mjs` (synchronized versions, and the in-app changelog in check mode)
15. Dart formatting (`dart format --set-exit-if-changed`)
16. `flutter analyze` and `flutter test` on `pi_frame_protocol`, `pi_frame_theme` and `pi_frame`
17. with `--release`: `flutter build web` and `flutter build <desktop>`
18. with `--e2e`: emulated-iPhone test

## Formatting

`pnpm run format` formats everything; `pnpm run format -- dart` or `-- ts` does one language, and `pnpm run format:check` only checks (what steps 2 and 15 run). Dart uses `dart format` with page width 120 (set in each Dart project's `analysis_options.yaml`); TypeScript and Node tooling (`apps/agentd`, `packages/pcp-*`, `test/e2e`, `tools`) use Prettier with `.prettierrc.json`. `tools/recon/reference/` holds verbatim upstream files and is excluded; `.prettierignore` also lists Markdown, YAML, JSON, the website and the Flutter app so an editor running Prettier agrees with the gate. Prettier uses `endOfLine: "auto"`: Windows checkouts (`core.autocrlf`) have CRLF files while git stores LF, so line endings are left to git. The Dart check covers each project's `lib/` and `test/` (the only Dart folders today); a new Dart folder such as `bin/` or `integration_test/` must be added to `tools/scripts/format.mjs`, and a new Dart project to `tools/scripts/flutter-projects.json`.

The one-time reformat commit is listed in `.git-blame-ignore-revs`: GitHub skips it in blame views automatically; locally run `git config blame.ignoreRevsFile .git-blame-ignore-revs` once. **Other branches** that existed before the reformat: run `pnpm run format` on them and commit before merging, and most conflicts disappear.

## In-app changelog

`apps/pi_frame/assets/CHANGELOG.md` (the post-update popup) is a generated copy of the root `CHANGELOG.md` and is not committed. `node tools/scripts/sync-changelog.mjs` (`pnpm run sync:changelog`) writes it; `pnpm run setup`, `run:app`, `run:app:dev`, the packaging scripts and the release workflow run it before Flutter. Step 13 only checks it: a missing or stale copy fails with the command that fixes it, and nothing is written. If the version check fails after you pulled a new release, run that command (or `pnpm run setup`). The decision logic is `syncChangelog` in `tools/guardrails`.

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
- Some tests regenerate tracked screenshots (`docs/design-evidence`, `website/assets`). This is not an error, but if you see them changed in your tree after running tests by hand, **do not commit them** (`git checkout -- docs/design-evidence website/assets`). `verify` works in a throw-away worktree, so it does not leave them behind.
- It is a local check and can be bypassed. It does not replace the GitHub workflows; it protects them from avoidable failures.

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
- **Packages.** `agentd` (`apps/agentd`), `pcp-ts`, `pcp-spec`, `pi_frame_protocol`, `pi_frame_theme` (`packages/*`), `pi_frame` (`apps/pi_frame`), `tools` (`tools/`) and `e2e` (`test/e2e`). Each is split into `lib` and `test`: a file is test code when it sits in a `test`, `tests` or `__tests__` folder of its package, or is named `*_test.dart`, `*.test.*` or `*.spec.*`. Files elsewhere in the repository are not audited, nor anything in `node_modules`, `dist`, `build`, `out`, `coverage` or `.dart_tool` folders. The audit's own source and tests (`tools/guardrails/*/escape-hatches*`) spell out every pattern and are skipped.
- **Baseline.** Every package × `lib`/`test` × pattern is listed, zeros included, so a first hatch in a clean area fails too. It counts per package, not per file: moving a hatch between files of the same package passes.
- **A count went up**: the message names the files and lines with that pattern (files changed since the baseline was last committed first, marked `(changed)`: one of them holds the new hatch) and how to fix the root cause. Fix the code; do not raise the baseline. Raising it is a human's decision (the `human-approved` label on the pull request).
- **A count went down**: the message gives the exact edit, for example `"agentd" → "lib": change "as any": 44 to "as any": 43`. Make it in the same commit.

The logic is `auditEscapeHatches` in `tools/guardrails/src/escape-hatches.mjs` (pure, tested with in-memory fixtures in `tools/guardrails/test/escape-hatches.test.mjs`); the script only reads the files (tracked plus untracked, not ignored, as they are on disk) and the baseline.

## Guardrail approval

`.github/workflows/guardrails-approval.yml` runs on every pull-request event (`opened`, `synchronize`, `reopened`, `labeled`, `unlabeled`). It is a separate workflow, not a `ci.yml` job, because `ci.yml`'s jobs must equal the step list's `ci` tier. It fails while the PR loosens a guardrail without a current `human-approved` label:

- **A raised baseline number**: any count in `tools/guardrails/escape-hatch-baseline.json` that is higher on the PR head than at its merge base. Lowering is free.
- **A guarded path changed**, in either direction: every `analysis_options.yaml`, `tsconfig*.json`, `.prettierrc.json` and `.prettierignore`, any ESLint config (`.eslintrc*`, `.eslintignore`, `eslint.config.*`), `tools/guardrails/**` (except the baseline file, see above), `tools/scripts/format.mjs`, `tools/scripts/flutter-projects.json`, `tools/scripts/audit-escape-hatches.mjs`, `tools/scripts/guardrails-approval.mjs`, `.github/workflows/**`, and the agent guards: `.claude/settings.json`, `.claude/hooks/**`, `.pi/extensions/**`, `.codex/rules/**`.

When approval is needed, the job posts **one** comment (found again by a hidden `<!-- guardrails-approval -->` marker and edited, never duplicated) listing each reason, for example ``agentd lib `as any` 44 → 45`` or ``CI workflow changed: `.github/workflows/ci.yml` ``. To approve, review the PR and add the label in the GitHub UI: the `labeled` event re-runs the job, which turns green and updates the comment; no push is needed. A PR that needs nothing passes silently, without a comment (if an earlier commit needed approval and no longer does, the existing comment says so).

**Staleness.** An approval counts only if the label was added after the latest push. Commit dates are written by whoever commits, so they are never used. The push time is one GitHub records: the creation time of the run itself when a push triggered it (`opened`, `synchronize`, `reopened`), otherwise the creation time of the newest `ci.yml` pull-request run for the head commit (`ci.yml` runs on exactly those events). On a push after approval the job fails, says in the comment that the approval is stale, and removes the label, so approving again is one click. If no push time can be found, any label counts as stale.

**Trust.** The job checks out the PR's **base** commit and runs the approval script from there; the PR head is fetched as data (its baseline file and changed paths) and never executed, so a PR cannot change the logic that judges it. The exception is bootstrap: while the base branch has no approval script, the PR's copy runs. The workflow file itself still comes from the PR (a `pull_request` workflow always does), so review any change to it by eye. Fork PRs get a read-only token: the verdict still holds, only the comment and the label removal are skipped. The token has `contents: read`, `actions: read` (the run times) and `pull-requests: write` (the comment and the label), and the job uses no secrets.

Try it locally (no GitHub access, so no labels: prints the verdict and the comment it would post):

```bash
node tools/scripts/guardrails-approval.mjs --base origin/main --head HEAD
```

The logic is `approvalStatus` in `tools/guardrails/src/approval.mjs` (pure, tested in `tools/guardrails/test/approval.test.mjs`); the script only reads git and GitHub and writes the comment. To make the check blocking, mark `Guardrail approval` as a required status check in the branch protection settings (a manual repository setting).

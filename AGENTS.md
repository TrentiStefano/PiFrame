# PiFrame agent map

A desktop and web frontend for the Pi coding agent. This file is a map: it stays under 100 lines, and the gate
fails when it names a path or `pnpm run` script that does not exist (`tools/guardrails/src/agent-map.mjs`).

## Rules

1. **Real captures only.** Show the PiFrame interface with real screenshots or recordings of the running Flutter app,
   never an HTML/CSS/canvas mockup. The curated captures that `DESIGN.md` references live in `docs/design/screens/`;
   take new ones with the UI harness (`.agents/skills/piframe-ui-harness/SKILL.md`), never from a test run.
2. **Real numbers only.** Quote actual repository links, release targets and verified capabilities; no invented
   metrics such as star or user counts.
3. **MCP tools.** The Flutter and Dart MCP tools are available in this environment; use them.
4. **Fixes leave a check.** A bug fix adds a regression test, or a lint for a recurring pattern.
   `docs/troubleshooting.md` changes only for problems users must work around; `docs/install.md` only when
   installing or operating the app changes; a user-facing feature is described in `docs/user-guide.md`, under
   its feature. Developer tooling is documented in the developer docs (`docs/pr-verification.md`, the package READMEs).
5. **Green gate, no escape hatches.** Fix the root cause; never add `// ignore:`, `@ts-ignore`, `as any`, `: any`
   or similar to pass a check: the escape-hatch audit fails on any new one.

## Layers

```text
apps/pi_frame (Flutter)  --PCP: HTTP + WebSocket on 127.0.0.1-->  apps/agentd (pi-agentd, Node 22)
apps/agentd  --one `pi --mode rpc` worker per session-->  Pi  --history-->  ~/.pi/agent/sessions
```

| Folder | Holds |
| :--- | :--- |
| `apps/pi_frame/` | Flutter app (Windows, macOS, Linux, web build for remote access) |
| `apps/agentd/` | the daemon: runs Pi workers, journals and replays events, Git and file access |
| `packages/pcp-spec/` | PCP specification and JSON Schemas: the protocol source of truth |
| `packages/pcp-ts/`, `packages/pi_frame_protocol/` | generated TypeScript and Dart PCP types |
| `packages/pi_frame_theme/` | theme engine and design tokens; theme files in `themes/` |
| `tools/` | `tools/guardrails/` gate logic, `tools/scripts/`, `tools/codegen/`, `tools/harness/` UI harness, `tools/fake-pi/` |
| `test/e2e/` | end-to-end tests with fault injection |
| `docs/` | install, user and troubleshooting guides, security, theming, verification, ADRs, design evidence |
| `website/` | project site (GitHub Pages) |
| `packaging/`, `release-assets/` | installer packaging and release artwork |

## Commands

| Job | Command |
| :--- | :--- |
| setup (once) | `pnpm run setup` |
| run the app (dev state in `~/.piframe-dev`) | `pnpm run run:app:dev` |
| run the daemon only | `pnpm run run:daemon` |
| inner loop, after every small change | `pnpm run check`, plus test files: `pnpm run check -- tools/guardrails/test/steps.test.mjs` |
| full gate, before a PR (commit first) | `pnpm run verify`; add `-- --release` before a release, `-- --e2e` for the remote web test |
| open a PR (verify, push, `gh pr create`) | `pnpm run pr` |
| format / check formatting | `pnpm run format` / `pnpm run format:check` |
| regenerate PCP types after a schema change | `pnpm run codegen` |
| drive the app off-screen, real screenshots | `pnpm run harness` (`tools/harness/README.md`) |
| all tests / end-to-end tests | `pnpm run test` / `pnpm run test:e2e` |

`check` runs in the working tree: the escape-hatch audit, the doc link and map checks, the DESIGN.md lint and token
match, TypeScript build and types, and
`flutter analyze`. `*_test.dart` files run with `flutter test`, `*.test.mjs` with `node --test`, and
`apps/agentd/src/**/*.test.ts` from its compiled copy under dist. `verify` runs the CI steps on the committed
HEAD merged with origin/main. Tests regenerate screenshots under `docs/design-evidence/` and
`website/assets/`: restore them with `git checkout -- docs/design-evidence website/assets` instead of committing.
Details: `docs/pr-verification.md`.

## Conventions

- **Flutter app** (`apps/pi_frame/README.md`), layers in `apps/pi_frame/lib/`: app (shell, routing), data (Riverpod
  providers and services, `docs/adr/0004-flutter-state-management.md`), domain (plain models), features (one folder
  per UI area), ui (shared widgets). Colours, spacing and motion come from `packages/pi_frame_theme/` (a lint rejects
  hardcoded colours); user-facing text goes through `apps/pi_frame/lib/data/language/`.
- **Design**: `DESIGN.md` (Google's DESIGN.md format) is the design system: tokens, components, states, the anti-slop
  gate and the definition of done for UI work. Its tokens must match `themes/` and `packages/pi_frame_theme/` (gate).
- **Daemon**: one folder per module in `apps/agentd/src/` (commands, journal, pi, server, sessions, side, workspace,
  ...); tests sit in each module's own test folder as `*.test.ts`, for example `apps/agentd/src/journal/test/`.
- **Protocol**: change `packages/pcp-spec/schema/` first, then `pnpm run codegen`; the gate fails on drift
  (`docs/adr/0003-protocol-source-of-truth.md`).
- **Gate checks**: pure logic in `tools/guardrails/src/` with in-memory tests in `tools/guardrails/test/`; a thin
  script in `tools/scripts/` does the I/O. Add the step to `tools/guardrails/src/steps.mjs`, then the same step to
  `.github/workflows/ci.yml` (the parity test prints the YAML). Guarded paths (`tools/guardrails/src/approval.mjs`)
  need the human-approved label on the PR.

## Workflow

grill the idea (`grilling` skill) → spec as a GitHub issue → tickets as sub-issues → implement test-first (`tdd`
skill) → PR with `pnpm run pr` (`pr` skill for the body). Decisions go to `docs/adr/`.

## Agent skills

- **Issue tracker**: GitHub Issues for TrentiStefano/PiFrame via the `gh` CLI; see `docs/agents/issue-tracker.md`.
- **Triage labels**: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`; see
  `docs/agents/triage-labels.md`.
- **Domain docs**: single context, one root `GLOSSARY.md` plus the ADRs in `docs/adr/`; see `docs/agents/domain.md`.
- **Glossary**: `GLOSSARY.md` gives each core concept one name; use it, not the aliases it lists to avoid.
- **UI**: `.agents/skills/piframe-ui-harness/SKILL.md` (drive and capture the app) and
  `.agents/skills/piframe-ui-preview/SKILL.md`.

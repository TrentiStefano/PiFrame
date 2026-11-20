# Local verification before a pull request

`ci.yml` checks every pull request, but the release workflow (`release.yml`, with its Windows and macOS installer builds) only starts after a merge into `main`: if it fails there, it has already used runner minutes (Windows ×2, macOS ×10) and `main` is broken. These two commands run the same steps **on your machine**, before the PR.

## Commands

```bash
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

## What it checks

`verify` checks the current **commit** (`HEAD`) merged with `origin/main`, in a temporary worktree next to the repository (`<repo>-verify-<pid>`, not in the system temp folder: some tests fail when the repository is there). It checks what `main` will be after the merge, not only your branch. If the merge with `origin/main` has conflicts, it stops and tells you.

The steps come from one shared step list, `tools/guardrails/src/steps.mjs`. `verify` runs its `verify` tier, and `.github/workflows/ci.yml` (which runs on every pull request and on pushes to `main`) runs its `ci` tier: the same steps, split into a Node and a Flutter job. A parity test in `tools/guardrails` fails when `ci.yml` drifts from the list, so to add or change a check, edit the step list first and then copy the YAML the test prints.

1. `pnpm install --frozen-lockfile`
2. `node tools/recon/verify.ts`
3. PCP schema validation
4. `pnpm -r run build` (including the daemon bundle build)
5. `pnpm -r run lint` (`tsc --noEmit` for every TypeScript package)
6. codegen parity (`tools/codegen/generate.js`: schema, TypeScript and Dart command/event types match)
7. `pnpm -r run test` (including the step-list and parity tests)
8. `pnpm run check:notices`
9. `pnpm run check:version` (synchronized versions)
10. `check:agentd-bundle` and `smoke:agentd-bundle`
11. Windows release-name tests
12. Flutter dependencies (`tools/scripts/setup-flutter.js`)
13. `flutter analyze` and `flutter test` on `pi_frame_protocol`, `pi_frame_theme` and `pi_frame`
14. with `--release`: `flutter build web` and `flutter build <desktop>`
15. with `--e2e`: emulated-iPhone test

The full output is in `.git/verify-ci/last.log`. If a step fails, the script prints the last lines and stops: with `pnpm run pr`, nothing is pushed and no PR is opened.

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

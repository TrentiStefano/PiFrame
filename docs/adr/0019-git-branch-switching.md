# ADR 0019: Git Branch Switching and Safe Worktree Stashing

- **Status:** Accepted
- **Confirmation Date:** 2026-11-05

## Context

Desktop and remote clients require visibility into repository branches and the ability to switch branches safely without leaving the PiFrame UI. However, branch switching in a live agent environment introduces substantial risk:
1. Agent processes may concurrently read or modify files in the working directory.
2. Uncommitted or untracked changes in the working tree may conflict with target branch revisions or be lost.
3. Untrusted or malicious branch names (e.g. CLI option injection `-rf`, ref traversal `@{-1}`, `..`, or control characters) could execute unexpected operations if passed unsanitized to Git.
4. Remote connections must not bypass permission boundaries (view mode versus control mode).

## Decision

Implement branch listing and switching within the daemon (`apps/agentd/src/workspace/`) under strict safety guarantees:

1. **Protocol Commands and Session Scope:**
   - `workspace.listBranches` (payload `{}`): read-only, permitted in remote `view` mode (`VIEW_ALLOWED`). Returns all local branches sorted with the current branch first, followed by `lastCommitUnix` descending. Correctly reports upstream tracking state (`ahead`, `behind`, or `null`) and detached HEAD status. On empty repositories without commits, returns `branches: []` and resolves `currentBranch` from `git symbolic-ref --short HEAD`.
   - `workspace.switchBranch` (payload `{ branch, onDirty }`): mutating, restricted to `control` mode (`CONTROL_EXTRA`) and local connections. Rejected while session is read-only or the Pi worker is active/streaming via `assertWorkspaceWritable`.
   - Both commands derive repository root strictly from session context; client-supplied cwd is ignored.

2. **Strict Branch Name Validation:**
   - Candidate branch names must be non-empty strings between 1 and 255 characters.
   - Names with leading `-` (option injection defense), whitespace, ASCII control characters (`\x00-\x1f\x7f`), `HEAD`, or `@{-N}` reflog expansions are immediately rejected with `BRANCH_INVALID_NAME` before executing any switch.
   - The name is validated via `git check-ref-format --branch <name>`.
   - Existence is confirmed against local branches via `git rev-parse --verify --quiet refs/heads/<name>` (rejecting remote-only tracking branches) with error code `BRANCH_NOT_FOUND`.

3. **Dirty Worktree Protection & Stashing (`onDirty` Policy):**
   - Uncommitted changes (modified, added, deleted, renamed, or untracked non-ignored files) are detected via `git status --porcelain=v1 -z`.
   - `onDirty: 'block'` (default): if the working directory is dirty, switching is rejected with `WORKSPACE_DIRTY` and details `{ changedFiles, untrackedFiles }`. No files are touched and no branch switch occurs.
   - `onDirty: 'stash'`: an untracked-inclusive stash is pushed with a standardized message `piframe: before switching to <name> (<iso time>)`. Creation of the stash is recorded via exact commit SHA (`git rev-parse -q --verify refs/stash`) and verified against the message via `git stash list --format=%gd%x00%H%x00%gs`. If `stash push` exits 0 but no new stash was created (nothing to stash), switching proceeds without claiming stashed state. If the subsequent `git switch --no-guess -- <name>` fails, the daemon resolves the exact stash matching that commit SHA (`stash@{n}`) and invokes `git stash pop stash@{n}` on the original branch to restore the exact pre-switch worktree state, leaving any interim foreign stashes intact. If the stash cannot be found or pop fails, the stash is retained and reported via `BRANCH_SWITCH_FAILED` details `{ stderr, stashRetained: true, stashMessage }`.
   - Destructive operations (`git reset --hard`, `git clean -fd`, `checkout -f`, or `--discard-changes`) are never executed.

4. **Concurrency & Cache Invalidation:**
   - All mutating repository operations are serialized per repository canonical root path.
   - The status cache is invalidated upon mutation. The client Git Changes panel refreshes status explicitly after command completion, consistent with `workspace.gitAction`.

## Consequences

- Worktree modifications are never silently overwritten or discarded.
- Branch operations are completely immune to shell and argument injection because arguments travel as fixed arrays to `execFile` without a shell.
- Remote `view` clients can inspect branches and tracking status without gaining write capabilities.

## Alternatives Rejected

- **Client-Side Git Execution:** Rejected. The Flutter client does not and should not have direct Git CLI execution capabilities or filesystem paths (especially across WSL / remote boundaries). The daemon remains the single authority on repository state, cache management, and session locking.
- **Auto-Pop After Switch:** Rejected. Automatically popping a stash from branch A onto branch B introduces high risk of merge conflicts, untracked collisions, and difficult-to-resolve index states across differing commit histories. The stash belongs to the originating branch history and should be restored explicitly by user intent.
- **Force Checkout (`git checkout -f` / `--discard-changes`):** Rejected. Silent loss of developer code is unacceptable. Mutating branch changes must require explicit stashing or a clean working tree.

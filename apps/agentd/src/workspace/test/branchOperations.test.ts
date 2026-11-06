import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import { WorkspaceService } from '../WorkspaceService.js';
import {
  validateBranchName,
  listGitBranches,
  switchGitBranch,
  getGitDirtyState,
} from '../gitClient.js';

function createTempRepo(opts: { initBranch?: string; commit?: boolean } = {}): {
  root: string;
  git: (args: string[]) => string;
  cleanup: () => void;
} {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-branch-test-'));
  const git = (args: string[]) =>
    execFileSync('git', args, { cwd: root, encoding: 'utf8' });

  const initBranch = opts.initBranch || 'main';
  git(['init', '-q', '-b', initBranch]);
  git(['config', 'user.email', 'test@example.com']);
  git(['config', 'user.name', 'PiFrame Test']);
  git(['config', 'core.autocrlf', 'false']);

  if (opts.commit !== false) {
    fs.writeFileSync(path.join(root, 'file.txt'), 'initial\n');
    git(['add', 'file.txt']);
    git(['commit', '-qm', 'initial commit']);
  }

  return {
    root,
    git,
    cleanup: () => {
      try {
        fs.rmSync(root, { recursive: true, force: true });
      } catch {}
    },
  };
}

test('validateBranchName: accepts weird valid names and rejects invalid names', async () => {
  const repo = createTempRepo();
  try {
    const validNames = [
      'feature/ä-ü',
      'fix#12',
      "it's",
      'a.b-c_d',
      'emoji-🚀',
    ];

    for (const name of validNames) {
      const validated = await validateBranchName(repo.root, name);
      assert.equal(validated, name);
    }

    const invalidNames = [
      '-rf',
      'a..b',
      'a b',
      'x.lock',
      'HEAD',
      '@{-1}',
      'bad\x01name',
      '',
      'a'.repeat(256),
      null,
      undefined,
      123,
    ];

    for (const name of invalidNames) {
      await assert.rejects(
        async () => validateBranchName(repo.root, name),
        (err: any) => {
          assert.equal(err.code, 'BRANCH_INVALID_NAME');
          return true;
        },
        `Expected rejection for branch name: ${String(name)}`
      );
    }
  } finally {
    repo.cleanup();
  }
});

test('listBranches: empty repository returns branches [] and currentBranch from symbolic-ref', async () => {
  const repo = createTempRepo({ commit: false });
  try {
    const service = new WorkspaceService();
    const result = await service.listBranches(repo.root);

    assert.deepEqual(result.branches, []);
    assert.equal(result.currentBranch, 'main');
    assert.equal(result.detached, false);
    assert.equal(result.headShortSha, null);
  } finally {
    repo.cleanup();
  }
});

test('listBranches: parses branches, sorting (current first, lastCommit desc), upstream, and detached HEAD', async () => {
  const repo = createTempRepo();
  try {
    const { git, root } = repo;

    // Create weird-named branch
    git(['branch', 'feature/ä-ü']);
    git(['branch', 'fix#12']);
    git(['branch', 'emoji-🚀']);

    // Advance fix#12 with a commit with explicit future date so its committer date is strictly newer
    git(['switch', 'fix#12']);
    fs.writeFileSync(path.join(root, 'fix.txt'), 'fixed\n');
    git(['add', 'fix.txt']);
    execFileSync('git', ['commit', '-qm', 'fix commit'], {
      cwd: root,
      env: {
        ...process.env,
        GIT_COMMITTER_DATE: '2035-01-01T00:00:00Z',
        GIT_AUTHOR_DATE: '2035-01-01T00:00:00Z',
      },
    });

    // Switch back to main
    git(['switch', 'main']);

    // Set upstream tracking for emoji-🚀 -> main
    git(['branch', '--set-upstream-to=main', 'emoji-🚀']);

    const service = new WorkspaceService();
    const result = await service.listBranches(root);

    assert.equal(result.currentBranch, 'main');
    assert.equal(result.detached, false);
    assert.ok(result.headShortSha);

    // Current branch (main) must be first
    assert.equal(result.branches[0].name, 'main');
    assert.equal(result.branches[0].isCurrent, true);

    // Second should be fix#12 because it has the newer commit
    assert.equal(result.branches[1].name, 'fix#12');
    assert.equal(result.branches[1].isCurrent, false);

    // Check upstream tracking on emoji-🚀
    const emojiBranch = result.branches.find((b) => b.name === 'emoji-🚀');
    assert.ok(emojiBranch);
    assert.equal(emojiBranch.upstream, 'main');
    assert.equal(typeof emojiBranch.ahead, 'number');
    assert.equal(typeof emojiBranch.behind, 'number');

    // Branch without upstream has nulls
    const fixBranch = result.branches.find((b) => b.name === 'fix#12');
    assert.ok(fixBranch);
    assert.equal(fixBranch.upstream, null);
    assert.equal(fixBranch.ahead, null);
    assert.equal(fixBranch.behind, null);

    // Test detached HEAD
    git(['checkout', '--detach', 'HEAD']);
    const detachedResult = await service.listBranches(root);
    assert.equal(detachedResult.currentBranch, null);
    assert.equal(detachedResult.detached, true);
    assert.ok(detachedResult.headShortSha);
    for (const b of detachedResult.branches) {
      assert.equal(b.isCurrent, false);
    }
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: invalid name and nonexistent branch rejections', async () => {
  const repo = createTempRepo();
  try {
    const service = new WorkspaceService();

    // Invalid branch name rejected before switch
    await assert.rejects(
      async () => service.switchBranch(repo.root, '-rf'),
      { code: 'BRANCH_INVALID_NAME' }
    );
    await assert.rejects(
      async () => service.switchBranch(repo.root, 'HEAD'),
      { code: 'BRANCH_INVALID_NAME' }
    );
    await assert.rejects(
      async () => service.switchBranch(repo.root, '@{-1}'),
      { code: 'BRANCH_INVALID_NAME' }
    );

    // Nonexistent branch
    await assert.rejects(
      async () => service.switchBranch(repo.root, 'does-not-exist'),
      { code: 'BRANCH_NOT_FOUND' }
    );
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: already on that branch is a success no-op', async () => {
  const repo = createTempRepo();
  try {
    const service = new WorkspaceService();

    // Clean already-current
    const res1 = await service.switchBranch(repo.root, 'main');
    assert.deepEqual(res1, {
      currentBranch: 'main',
      stashed: false,
      stashMessage: null,
    });

    // Dirty already-current: still a no-op, files untouched
    fs.writeFileSync(path.join(repo.root, 'dirty.txt'), 'dirty\n');
    const res2 = await service.switchBranch(repo.root, 'main', 'block');
    assert.deepEqual(res2, {
      currentBranch: 'main',
      stashed: false,
      stashMessage: null,
    });
    assert.ok(fs.existsSync(path.join(repo.root, 'dirty.txt')));
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: clean switch success including weird names and from detached HEAD', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature/ä-ü']);
    const service = new WorkspaceService();

    // Clean switch to weird name
    const res = await service.switchBranch(repo.root, 'feature/ä-ü');
    assert.deepEqual(res, {
      currentBranch: 'feature/ä-ü',
      stashed: false,
      stashMessage: null,
    });
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'feature/ä-ü');

    // Detach HEAD
    repo.git(['checkout', '--detach', 'HEAD']);
    assert.equal(repo.git(['branch', '--show-current']).trim(), '');

    // Switch from detached HEAD to main
    const res2 = await service.switchBranch(repo.root, 'main');
    assert.deepEqual(res2, {
      currentBranch: 'main',
      stashed: false,
      stashMessage: null,
    });
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'main');
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: dirty working directory with onDirty block leaves files untouched', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);

    // Create modified tracked file
    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'modified content\n');
    // Create staged file
    fs.writeFileSync(path.join(repo.root, 'staged.txt'), 'staged content\n');
    repo.git(['add', 'staged.txt']);
    // Create untracked file
    fs.writeFileSync(path.join(repo.root, 'untracked.txt'), 'untracked content\n');

    const service = new WorkspaceService();

    // Default onDirty is 'block'
    await assert.rejects(
      async () => service.switchBranch(repo.root, 'feature'),
      (err: any) => {
        assert.equal(err.code, 'WORKSPACE_DIRTY');
        assert.equal(err.details?.changedFiles, 2); // file.txt (mod) + staged.txt (staged)
        assert.equal(err.details?.untrackedFiles, 1); // untracked.txt
        return true;
      }
    );

    // Verify files remain untouched and branch unchanged
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'main');
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'modified content\n');
    assert.equal(fs.readFileSync(path.join(repo.root, 'staged.txt'), 'utf8'), 'staged content\n');
    assert.equal(fs.readFileSync(path.join(repo.root, 'untracked.txt'), 'utf8'), 'untracked content\n');

    // Explicit onDirty: 'block'
    await assert.rejects(
      async () => service.switchBranch(repo.root, 'feature', 'block'),
      { code: 'WORKSPACE_DIRTY' }
    );
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: dirty working directory with onDirty stash creates stash and switches branch', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);

    // Modified tracked file + untracked file
    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'stashed modification\n');
    fs.writeFileSync(path.join(repo.root, 'untracked.txt'), 'stashed untracked\n');

    const service = new WorkspaceService();
    const result = await service.switchBranch(repo.root, 'feature', 'stash');

    assert.equal(result.currentBranch, 'feature');
    assert.equal(result.stashed, true);
    assert.ok(result.stashMessage);
    assert.match(
      result.stashMessage,
      /^piframe: before switching to feature \(\d{4}-\d{2}-\d{2}T/
    );

    // Working directory on new branch is clean
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'feature');
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'initial\n');
    assert.ok(!fs.existsSync(path.join(repo.root, 'untracked.txt')));

    // Stash exists in git stash list and can be recovered
    const stashList = repo.git(['stash', 'list', '-n', '1']);
    assert.ok(stashList.includes(result.stashMessage));

    // Pop stash on original branch to verify content recoverability
    repo.git(['switch', 'main']);
    repo.git(['stash', 'pop']);
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'stashed modification\n');
    assert.equal(fs.readFileSync(path.join(repo.root, 'untracked.txt'), 'utf8'), 'stashed untracked\n');
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: stash + switch failure path pops stash back with nothing lost', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);

    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'dirty content\n');
    fs.writeFileSync(path.join(repo.root, 'new.txt'), 'new untracked\n');

    const service = new WorkspaceService();

    // Inject switch failure
    const hooks = {
      injectSwitchFailure: async () => {
        const error: any = new Error('Simulated git switch checkout failure');
        error.code = 'GIT_FAILED';
        error.stderr = 'fatal: simulated collision in switch';
        throw error;
      },
    };

    await assert.rejects(
      async () => service.switchBranch(repo.root, 'feature', 'stash', undefined, hooks),
      (err: any) => {
        assert.equal(err.code, 'BRANCH_SWITCH_FAILED');
        assert.ok(err.details?.stderr?.includes('simulated collision in switch'));
        // stashRetained should not be true because pop succeeded
        assert.equal(err.details?.stashRetained, undefined);
        return true;
      }
    );

    // Check that we are still on main, stash was popped, and files are intact!
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'main');
    assert.equal(fs.readFileSync(path.join(repo.root, 'file.txt'), 'utf8'), 'dirty content\n');
    assert.equal(fs.readFileSync(path.join(repo.root, 'new.txt'), 'utf8'), 'new untracked\n');

    // Stash list should be empty
    const stashList = repo.git(['stash', 'list']);
    assert.equal(stashList.trim(), '');
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: stash + switch failure + pop failure leaves stash and reports stashRetained', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);

    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'important content\n');

    const service = new WorkspaceService();

    // Inject switch failure AND pop failure
    const hooks = {
      injectSwitchFailure: async () => {
        const error: any = new Error('Simulated switch failure');
        error.code = 'GIT_FAILED';
        error.stderr = 'fatal: switch exploded';
        throw error;
      },
      injectPopFailure: async () => {
        const error: any = new Error('Simulated pop conflict failure');
        error.code = 'GIT_FAILED';
        error.stderr = 'fatal: stash pop collision';
        throw error;
      },
    };

    await assert.rejects(
      async () => service.switchBranch(repo.root, 'feature', 'stash', undefined, hooks),
      (err: any) => {
        assert.equal(err.code, 'BRANCH_SWITCH_FAILED');
        assert.equal(err.details?.stashRetained, true);
        assert.ok(err.details?.stashMessage?.startsWith('piframe: before switching to feature'));
        assert.ok(err.details?.stderr?.includes('switch exploded'));
        return true;
      }
    );

    // Verify stash remains in git stash list intact
    const stashList = repo.git(['stash', 'list']);
    assert.ok(stashList.includes('piframe: before switching to feature'));
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: rollback restores PiFrame stash and preserves interim foreign stash', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);

    // PiFrame worktree changes
    fs.writeFileSync(path.join(repo.root, 'piframe.txt'), 'piframe uncommitted\n');

    const service = new WorkspaceService();

    // Push an extra foreign stash between PiFrame's stash push and switch failure
    const hooks = {
      injectSwitchFailure: async () => {
        fs.writeFileSync(path.join(repo.root, 'foreign.txt'), 'foreign uncommitted\n');
        repo.git(['stash', 'push', '--include-untracked', '-m', 'foreign interim stash']);
        const error: any = new Error('Simulated git switch checkout failure');
        error.code = 'GIT_FAILED';
        error.stderr = 'fatal: simulated collision in switch';
        throw error;
      },
    };

    await assert.rejects(
      async () => service.switchBranch(repo.root, 'feature', 'stash', undefined, hooks),
      (err: any) => {
        assert.equal(err.code, 'BRANCH_SWITCH_FAILED');
        assert.equal(err.details?.stashRetained, undefined);
        assert.ok(err.details?.stderr?.includes('simulated collision in switch'));
        return true;
      }
    );

    // Assert that we are still on main
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'main');

    // PiFrame's changes must be restored to working directory
    assert.equal(fs.readFileSync(path.join(repo.root, 'piframe.txt'), 'utf8'), 'piframe uncommitted\n');

    // Foreign file must NOT be in working directory
    assert.equal(fs.existsSync(path.join(repo.root, 'foreign.txt')), false);

    // Foreign stash must still be intact in git stash list
    const stashList = repo.git(['stash', 'list']);
    assert.ok(stashList.includes('foreign interim stash'));
    assert.ok(!stashList.includes('piframe: before switching to feature'));

    // Popping the remaining foreign stash recovers foreign work
    repo.git(['stash', 'pop']);
    assert.equal(fs.readFileSync(path.join(repo.root, 'foreign.txt'), 'utf8'), 'foreign uncommitted\n');
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: rollback when PiFrame stash commit sha is missing reports stashRetained: true', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);
    fs.writeFileSync(path.join(repo.root, 'file.txt'), 'piframe change\n');

    const service = new WorkspaceService();

    const hooks = {
      injectSwitchFailure: async () => {
        // Externally clear all stashes so the recorded SHA is not in the stash list
        repo.git(['stash', 'clear']);
        const error: any = new Error('Simulated switch failure');
        error.code = 'GIT_FAILED';
        error.stderr = 'fatal: switch exploded';
        throw error;
      },
    };

    await assert.rejects(
      async () => service.switchBranch(repo.root, 'feature', 'stash', undefined, hooks),
      (err: any) => {
        assert.equal(err.code, 'BRANCH_SWITCH_FAILED');
        assert.equal(err.details?.stashRetained, true);
        assert.match(err.details?.stashMessage, /^piframe: before switching to feature/);
        return true;
      }
    );
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: stash push exits 0 but nothing to stash proceeds with switch without claiming stashed', async () => {
  const repo = createTempRepo();
  try {
    repo.git(['branch', 'feature']);
    fs.writeFileSync(path.join(repo.root, 'race.txt'), 'about to vanish\n');

    const service = new WorkspaceService();

    // Remove the dirty file right before stash push runs
    const hooks = {
      injectBeforeStashPush: async () => {
        fs.rmSync(path.join(repo.root, 'race.txt'));
      },
    };

    const result = await service.switchBranch(repo.root, 'feature', 'stash', undefined, hooks);
    assert.deepEqual(result, {
      currentBranch: 'feature',
      stashed: false,
      stashMessage: null,
    });
    assert.equal(repo.git(['symbolic-ref', '--short', 'HEAD']).trim(), 'feature');
  } finally {
    repo.cleanup();
  }
});

test('listGitBranches: detached HEAD asserts isCurrent is false for all branches', async () => {
  const repo = createTempRepo();
  try {
    const { git, root } = repo;
    git(['branch', 'alpha']);
    git(['branch', 'beta']);

    // Detach HEAD at current commit
    git(['checkout', '--detach', 'HEAD']);

    const result = await listGitBranches(root);
    assert.equal(result.currentBranch, null);
    assert.equal(result.detached, true);
    assert.equal(result.branches.length, 3); // main, alpha, beta
    for (const b of result.branches) {
      assert.equal(b.isCurrent, false, `Branch '${b.name}' must have isCurrent === false on detached HEAD`);
    }
  } finally {
    repo.cleanup();
  }
});

test('switchBranch: switches correctly to a branch whose name equals an existing file path using --', async () => {
  const repo = createTempRepo();
  try {
    const { git, root } = repo;

    // Create a file named README.md and commit it
    fs.writeFileSync(path.join(root, 'README.md'), '# Test Readme\n');
    git(['add', 'README.md']);
    git(['commit', '-qm', 'chore: add README.md']);

    // Create a branch also named README.md
    git(['branch', 'README.md']);

    const service = new WorkspaceService();
    const result = await service.switchBranch(root, 'README.md');

    assert.equal(result.currentBranch, 'README.md');
    assert.equal(result.stashed, false);
    assert.equal(result.stashMessage, null);
    assert.equal(git(['symbolic-ref', '--short', 'HEAD']).trim(), 'README.md');
    assert.equal(fs.readFileSync(path.join(root, 'README.md'), 'utf8'), '# Test Readme\n');
  } finally {
    repo.cleanup();
  }
});


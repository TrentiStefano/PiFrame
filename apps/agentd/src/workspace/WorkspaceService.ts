import * as fs from 'node:fs';
import * as path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { checkIsGitRepo, getGitDiff, getGitStatus, getStagedPaths, runGitStrict, type GitStatusResult } from './gitClient.js';

type FileInfo = { path: string; sizeBytes: number };

const MAX_FILE_BYTES = 1024 * 1024;
const MAX_LIST_FILES = 10000;
const MAX_GIT_PATHS = 1000;

function workspaceError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

function inside(root: string, target: string): boolean {
  const relative = path.relative(root, target);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function normalizeRelativePath(input: unknown): string {
  if (typeof input !== 'string' || input.length === 0 || input.includes('\0') || input.includes('\\') ||
      path.posix.isAbsolute(input) || path.win32.isAbsolute(input) || /^[a-zA-Z]:/.test(input)) {
    throw workspaceError('Path must be a non-empty repository-relative path.', 'WORKSPACE_PATH_INVALID');
  }
  const segments = input.split('/');
  if (segments.some((segment) => segment === '..')) {
    throw workspaceError('Path traversal is not allowed.', 'WORKSPACE_PATH_INVALID');
  }
  const normalized = path.posix.normalize(input);
  if (!normalized || normalized === '.' || normalized.startsWith('../')) {
    throw workspaceError('Path must identify an item inside the repository.', 'WORKSPACE_PATH_INVALID');
  }
  return normalized;
}

function revision(bytes: Buffer): string {
  return createHash('sha256').update(bytes).digest('hex');
}

async function isTextFile(bytes: Buffer): Promise<string> {
  if (bytes.includes(0)) throw workspaceError('Binary files are not supported.', 'WORKSPACE_UNSUPPORTED_FILE');
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw workspaceError('File is not valid UTF-8 text.', 'WORKSPACE_UNSUPPORTED_FILE');
  }
}

export class WorkspaceService {
  private statusCache = new Map<string, { result: GitStatusResult; timestamp: number }>();
  private mutationQueues = new Map<string, Promise<unknown>>();
  private readonly CACHE_TTL_MS = 1000;

  async resolveRepositoryRoot(cwd: string): Promise<string> {
    const repo = await checkIsGitRepo(cwd);
    if (!repo.isRepo || !repo.rootPath) {
      throw workspaceError('Session working directory is not inside a Git repository.', 'WORKSPACE_NOT_REPOSITORY');
    }
    return fs.promises.realpath(repo.rootPath);
  }

  async getStatus(cwd: string, forceRefresh = false): Promise<GitStatusResult> {
    const repo = await checkIsGitRepo(cwd);
    if (!repo.isRepo || !repo.rootPath) return getGitStatus(cwd);
    const root = await fs.promises.realpath(repo.rootPath);
    const cached = this.statusCache.get(root);
    const now = Date.now();
    if (!forceRefresh && cached && now - cached.timestamp < this.CACHE_TTL_MS) return cached.result;
    const result = await getGitStatus(root);
    this.statusCache.set(root, { result, timestamp: now });
    return result;
  }

  async getDiff(cwd: string, filePath?: string): Promise<string> {
    const repo = await checkIsGitRepo(cwd);
    if (!repo.isRepo || !repo.rootPath) return '';
    const root = await fs.promises.realpath(repo.rootPath);
    const safePath = filePath === undefined ? undefined : await this.resolvePath(root, filePath, true);
    return getGitDiff(root, safePath ? path.relative(root, safePath).split(path.sep).join('/') : undefined);
  }

  async listFiles(cwd: string): Promise<{ rootPath: string; files: FileInfo[]; truncated: boolean }> {
    const root = await this.resolveRepositoryRoot(cwd);
    const output = await runGitStrict(['ls-files', '--cached', '--others', '--exclude-standard', '-z'], root);
    const files: FileInfo[] = [];
    let truncated = false;
    const items = output.split('\0').filter(Boolean);
    const BATCH_SIZE = 64;
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      if (files.length >= MAX_LIST_FILES) {
        truncated = true;
        break;
      }
      const chunk = items.slice(i, i + BATCH_SIZE);
      const results = await Promise.all(
        chunk.map(async (item) => {
          let relativePath: string;
          try {
            relativePath = normalizeRelativePath(item);
          } catch {
            return null;
          }
          const target = path.resolve(root, ...relativePath.split('/'));
          if (!inside(root, target)) return null;
          try {
            const entry = await fs.promises.lstat(target);
            if (!entry.isFile() || entry.isSymbolicLink()) return null;
            const canonical = await fs.promises.realpath(target);
            if (!inside(root, canonical)) return null;
            return { path: relativePath, sizeBytes: entry.size };
          } catch (error: any) {
            if (error?.code !== 'ENOENT') throw error;
            return null;
          }
        })
      );
      for (const res of results) {
        if (res) {
          files.push(res);
          if (files.length >= MAX_LIST_FILES) {
            truncated = true;
            break;
          }
        }
      }
    }
    files.sort((a, b) => a.path.localeCompare(b.path));
    return { rootPath: root, files, truncated };
  }

  async readFile(cwd: string, requestedPath: string): Promise<{ rootPath: string; path: string; content: string; revision: string; sizeBytes: number }> {
    const root = await this.resolveRepositoryRoot(cwd);
    const safePath = await this.resolvePath(root, requestedPath, false);
    const stat = await fs.promises.stat(safePath);
    if (!stat.isFile()) throw workspaceError('Only regular text files can be read.', 'WORKSPACE_UNSUPPORTED_FILE');
    if (stat.size > MAX_FILE_BYTES) throw workspaceError(`File exceeds ${MAX_FILE_BYTES} byte limit.`, 'WORKSPACE_FILE_TOO_LARGE');
    const bytes = await fs.promises.readFile(safePath);
    if (bytes.length > MAX_FILE_BYTES) throw workspaceError(`File exceeds ${MAX_FILE_BYTES} byte limit.`, 'WORKSPACE_FILE_TOO_LARGE');
    const content = await isTextFile(bytes);
    return { rootPath: root, path: path.relative(root, safePath).split(path.sep).join('/'), content, revision: revision(bytes), sizeBytes: bytes.length };
  }

  async saveFile(cwd: string, requestedPath: string, content: unknown, expectedRevision: unknown, assertCanWrite?: () => void): Promise<{ path: string; revision: string }> {
    const root = await this.resolveRepositoryRoot(cwd);
    const relativePath = normalizeRelativePath(requestedPath);
    if (typeof content !== 'string') throw workspaceError('File content must be text.', 'WORKSPACE_INVALID_CONTENT');
    const bytes = Buffer.from(content, 'utf8');
    if (bytes.length > MAX_FILE_BYTES) throw workspaceError(`File exceeds ${MAX_FILE_BYTES} byte limit.`, 'WORKSPACE_FILE_TOO_LARGE');
    if (typeof expectedRevision !== 'string' || !/^[a-f0-9]{64}$/.test(expectedRevision)) {
      throw workspaceError('A valid expected file revision is required.', 'WORKSPACE_REVISION_REQUIRED');
    }

    return this.serialize(root, async () => {
      assertCanWrite?.();
      const target = await this.resolvePath(root, relativePath, true, true);
      await this.assertRevision(target, expectedRevision);
      const parent = path.dirname(target);
      const mode = (await fs.promises.stat(target)).mode;
      const tempPath = path.join(parent, `.pi-crust-${randomUUID()}.tmp`);
      let handle: fs.promises.FileHandle | undefined;
      try {
        handle = await fs.promises.open(tempPath, 'wx', mode & 0o777);
        await handle.writeFile(bytes);
        await handle.sync();
        await handle.close();
        handle = undefined;
        // Recheck immediately before atomic replacement to avoid overwriting external edits.
        await this.assertRevision(target, expectedRevision);
        await fs.promises.rename(tempPath, target);
      } catch (error) {
        if (handle) await handle.close().catch(() => {});
        await fs.promises.unlink(tempPath).catch(() => {});
        throw error;
      }
      this.invalidate(root);
      return { path: relativePath, revision: revision(bytes) };
    });
  }

  async gitAction(cwd: string, action: unknown, pathsInput: unknown, expectedStagedPathsInput?: unknown, message?: unknown, assertCanWrite?: () => void): Promise<{ status: GitStatusResult }> {
    const root = await this.resolveRepositoryRoot(cwd);
    if (!['stage', 'unstage', 'commit', 'discard'].includes(String(action))) {
      throw workspaceError('Unsupported Git action.', 'WORKSPACE_GIT_ACTION_INVALID');
    }
    const actionName = String(action);
    const paths = this.normalizePaths(pathsInput, actionName === 'commit');
    const safePaths = await Promise.all(paths.map(async (item) => {
      await this.resolvePath(root, item, true, true);
      return item;
    }));

    return this.serialize(root, async () => {
      assertCanWrite?.();
      const beforeStatus = await getGitStatus(root);
      const byPath = new Map(beforeStatus.files.map((file) => [file.path, file]));
      if (actionName !== 'commit' && safePaths.some((item) => !byPath.has(item))) {
        throw workspaceError('Selected Git changes are stale; refresh before mutating.', 'WORKSPACE_STALE_STATUS');
      }
      if (actionName === 'stage') {
        await runGitStrict(['add', '--', ...safePaths], root);
      } else if (actionName === 'unstage') {
        if (safePaths.some((item) => !byPath.get(item)?.staged)) {
          throw workspaceError('Selected files are no longer staged.', 'WORKSPACE_STALE_STATUS');
        }
        await runGitStrict(['restore', '--staged', '--', ...safePaths], root);
      } else if (actionName === 'discard') {
        for (const item of safePaths) {
          const change = byPath.get(item)!;
          const target = await this.resolvePath(root, item, true, true);
          if (change.status === 'untracked') {
            await fs.promises.unlink(target);
            continue;
          }
          const existsInHead = await runGitStrict(['cat-file', '-e', `HEAD:${item}`], root).then(() => true, () => false);
          if (change.stagedStatus === 'A' && !existsInHead) {
            await runGitStrict(['rm', '--cached', '--force', '--', item], root);
            await fs.promises.unlink(target).catch((error: any) => { if (error?.code !== 'ENOENT') throw error; });
          } else {
            await runGitStrict(['restore', '--source=HEAD', '--staged', '--worktree', '--', item], root);
          }
        }
      } else {
        if (typeof message !== 'string' || message.trim().length === 0) {
          throw workspaceError('Commit message must not be empty.', 'WORKSPACE_COMMIT_MESSAGE_REQUIRED');
        }
        const expected = this.normalizePaths(expectedStagedPathsInput, false);
        if (expected.join('\0') !== safePaths.join('\0')) {
          throw workspaceError('Commit paths must match expectedStagedPaths exactly.', 'WORKSPACE_STAGED_SET_MISMATCH');
        }
        const actual = await getStagedPaths(root);
        if (actual.join('\0') !== expected.join('\0')) {
          throw workspaceError('Staged file set changed; refresh and confirm the staged files before committing.', 'WORKSPACE_STAGED_SET_MISMATCH');
        }
        await runGitStrict(['commit', '-m', message, '--'], root);
      }

      this.invalidate(root);
      const refreshedStatus = await getGitStatus(root);
      if (!refreshedStatus.isRepository) throw workspaceError('Git repository disappeared after mutation.', 'WORKSPACE_NOT_REPOSITORY');
      return { status: refreshedStatus };
    });
  }

  invalidate(cwd: string): void {
    this.statusCache.delete(cwd);
  }

  private normalizePaths(input: unknown, allowEmpty: boolean): string[] {
    if (!Array.isArray(input) || input.length > MAX_GIT_PATHS || (!allowEmpty && input.length === 0)) {
      throw workspaceError('Explicit repository-relative paths are required.', 'WORKSPACE_PATH_INVALID');
    }
    const paths = input.map(normalizeRelativePath).sort();
    if (new Set(paths).size !== paths.length) throw workspaceError('Duplicate paths are not allowed.', 'WORKSPACE_PATH_INVALID');
    return paths;
  }

  private async resolvePath(root: string, requestedPath: string, allowMissing: boolean, forWrite = false): Promise<string> {
    const relativePath = normalizeRelativePath(requestedPath);
    const target = path.resolve(root, ...relativePath.split('/'));
    if (!inside(root, target)) throw workspaceError('Path escapes repository root.', 'WORKSPACE_PATH_INVALID');
    const parent = path.dirname(target);
    let realParent: string;
    try {
      realParent = await fs.promises.realpath(parent);
    } catch {
      if (!allowMissing) throw workspaceError('File does not exist.', 'WORKSPACE_FILE_NOT_FOUND');
      throw workspaceError('Parent directory does not exist.', 'WORKSPACE_FILE_NOT_FOUND');
    }
    if (!inside(root, realParent)) throw workspaceError('Path escapes repository through a symlink.', 'WORKSPACE_PATH_INVALID');

    try {
      const entry = await fs.promises.lstat(target);
      if (forWrite && entry.isSymbolicLink()) throw workspaceError('Writes through symlinks are not allowed.', 'WORKSPACE_PATH_INVALID');
      const realTarget = await fs.promises.realpath(target);
      if (!inside(root, realTarget)) throw workspaceError('Path escapes repository through a symlink.', 'WORKSPACE_PATH_INVALID');
      if (!entry.isSymbolicLink() && !inside(root, realTarget)) throw workspaceError('Path escapes repository root.', 'WORKSPACE_PATH_INVALID');
      return forWrite ? target : realTarget;
    } catch (error: any) {
      if (error?.code !== 'ENOENT') throw error;
      if (!allowMissing) throw workspaceError('File does not exist.', 'WORKSPACE_FILE_NOT_FOUND');
      return target;
    }
  }

  private async assertRevision(target: string, expected: string): Promise<void> {
    let bytes: Buffer;
    try {
      const stat = await fs.promises.stat(target);
      if (!stat.isFile()) throw workspaceError('Only regular text files can be saved.', 'WORKSPACE_UNSUPPORTED_FILE');
      if (stat.size > MAX_FILE_BYTES) throw workspaceError(`File exceeds ${MAX_FILE_BYTES} byte limit.`, 'WORKSPACE_FILE_TOO_LARGE');
      bytes = await fs.promises.readFile(target);
    } catch (error: any) {
      if (error?.code === 'ENOENT') throw workspaceError('File changed or was removed; reload before saving.', 'WORKSPACE_REVISION_CONFLICT');
      throw error;
    }
    if (revision(bytes) !== expected) throw workspaceError('File changed on disk; reload before saving.', 'WORKSPACE_REVISION_CONFLICT');
  }

  private async serialize<T>(root: string, task: () => Promise<T>): Promise<T> {
    const previous = this.mutationQueues.get(root) || Promise.resolve();
    const current = previous.catch(() => {}).then(task);
    this.mutationQueues.set(root, current);
    try {
      return await current as T;
    } finally {
      if (this.mutationQueues.get(root) === current) this.mutationQueues.delete(root);
    }
  }
}

import { getGitStatus, getGitDiff, GitStatusResult } from './gitClient.js';

export class WorkspaceService {
  private statusCache = new Map<string, { result: GitStatusResult; timestamp: number }>();
  private readonly CACHE_TTL_MS = 1000;

  async getStatus(cwd: string, forceRefresh = false): Promise<GitStatusResult> {
    const cached = this.statusCache.get(cwd);
    const now = Date.now();

    if (!forceRefresh && cached && now - cached.timestamp < this.CACHE_TTL_MS) {
      return cached.result;
    }

    const result = await getGitStatus(cwd);
    this.statusCache.set(cwd, { result, timestamp: now });
    return result;
  }

  async getDiff(cwd: string, filePath?: string): Promise<string> {
    return getGitDiff(cwd, filePath);
  }

  invalidate(cwd: string): void {
    this.statusCache.delete(cwd);
  }
}

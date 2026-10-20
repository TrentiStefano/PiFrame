import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { getPiCrustBaseDir } from '../config/config.js';

export function isTemporarySessionCwd(cwd: string, tempDir = os.tmpdir()): boolean {
  const pathApi = path.win32.isAbsolute(cwd) || path.win32.isAbsolute(tempDir) ? path.win32 : path;
  const relative = pathApi.relative(pathApi.resolve(tempDir), pathApi.resolve(cwd));
  return relative === '' || (!relative.startsWith(`..${pathApi.sep}`) && relative !== '..' && !pathApi.isAbsolute(relative));
}

export interface SessionSummary {
  id: string;
  name?: string;
  cwd: string;
  gitRoot?: string | null;
  sessionFile: string;
  createdAt: number;
  lastActivityAt: number;
  sizeBytes: number;
  messageCount: number;
  lastMessagePreview?: string;
  isActive: boolean;
}

export class SessionIndex {
  private cachePath: string;
  private sessionsDir: string;
  private cache = new Map<string, { mtime: number; summary: SessionSummary }>();

  constructor(opts: { sessionsDir?: string; cachePath?: string } = {}) {
    this.sessionsDir = opts.sessionsDir || process.env.PI_CODING_AGENT_SESSION_DIR ||
      path.join(process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), '.pi', 'agent'), 'sessions');
    this.cachePath = opts.cachePath || path.join(getPiCrustBaseDir(), 'index.json');
    this.loadCache();
  }

  private loadCache(): void {
    if (fs.existsSync(this.cachePath)) {
      try {
        const raw = fs.readFileSync(this.cachePath, 'utf8');
        const list = JSON.parse(raw);
        for (const item of list) {
          if (item.id && item.mtime && item.summary) {
            this.cache.set(item.id, item);
          }
        }
      } catch {}
    }
  }

  private saveCache(): void {
    try {
      const list = Array.from(this.cache, ([id, value]) => ({ id, ...value }));
      fs.mkdirSync(path.dirname(this.cachePath), { recursive: true });
      const temp = `${this.cachePath}.tmp.${Date.now()}`;
      fs.writeFileSync(temp, JSON.stringify(list, null, 2), 'utf8');
      fs.renameSync(temp, this.cachePath);
    } catch {}
  }

  /**
   * Scans ~/.pi/agent/sessions/ strictly in read-only mode to index existing Pi sessions.
   */
  public async scan(activeSessionIds = new Set<string>()): Promise<SessionSummary[]> {
    const piSessionsDir = this.sessionsDir;
    if (!fs.existsSync(piSessionsDir)) {
      return [];
    }

    const summaries: SessionSummary[] = [];

    try {
      // Structure of ~/.pi/agent/sessions: <cwdHash_or_name>/<sessionFile.jsonl>
      const cwdDirs = fs.readdirSync(piSessionsDir);

      for (const cwdDir of cwdDirs) {
        const fullCwdDirPath = path.join(piSessionsDir, cwdDir);
        let stat: fs.Stats;
        try {
          stat = fs.statSync(fullCwdDirPath);
        } catch {
          continue;
        }
        const sessionFiles = stat.isDirectory()
          ? fs.readdirSync(fullCwdDirPath).map((file) => path.join(fullCwdDirPath, file))
          : [fullCwdDirPath];
        for (const fullFilePath of sessionFiles) {
          const sFile = path.basename(fullFilePath);
          if (!sFile.endsWith('.json') && !sFile.endsWith('.jsonl')) continue;
          let fileStat: fs.Stats;
          try {
            fileStat = fs.statSync(fullFilePath);
          } catch {
            continue;
          }

          const sessionId = path.basename(sFile, path.extname(sFile));
          const cached = this.cache.get(fullFilePath);

          if (cached && cached.mtime === fileStat.mtimeMs) {
            if (isTemporarySessionCwd(cached.summary.cwd)) continue;
            summaries.push({
              ...cached.summary,
              isActive: activeSessionIds.has(cached.summary.id)
            });
            continue;
          }

          // Inspect session file preview
          const summary = this.parseSessionFile(sessionId, fullFilePath, fileStat, cwdDir);
          if (!summary) continue;
          this.cache.set(fullFilePath, { mtime: fileStat.mtimeMs, summary });
          summaries.push({
            ...summary,
            isActive: activeSessionIds.has(summary.id)
          });
        }
      }

      this.saveCache();
    } catch (err) {
      console.error('Error scanning Pi sessions directory:', err);
    }

    // Sort descending by lastActivityAt
    return summaries.sort((a, b) => b.lastActivityAt - a.lastActivityAt);
  }

  public async listSessions(
    activeSessionIds = new Set<string>(),
    query?: string,
    limit: number = 50
  ): Promise<SessionSummary[]> {
    let list = await this.scan(activeSessionIds);

    if (query && query.trim().length > 0) {
      const q = query.trim().toLowerCase();
      list = list.filter(
        (s) =>
          s.id.toLowerCase().includes(q) ||
          (s.name && s.name.toLowerCase().includes(q)) ||
          s.cwd.toLowerCase().includes(q) ||
          (s.lastMessagePreview && s.lastMessagePreview.toLowerCase().includes(q))
      );
    }

    return list.slice(0, limit);
  }

  public removeSession(sessionId: string): string | null {
    let deletedPath: string | null = null;
    for (const [filePath, cached] of this.cache.entries()) {
      if (
        cached.summary.id === sessionId ||
        path.basename(filePath, path.extname(filePath)) === sessionId
      ) {
        deletedPath = filePath;
        this.cache.delete(filePath);
        break;
      }
    }
    if (deletedPath && fs.existsSync(deletedPath)) {
      try {
        fs.unlinkSync(deletedPath);
      } catch (err) {
        console.error('Failed to unlink session file:', deletedPath, err);
      }
    }
    this.saveCache();
    return deletedPath;
  }

  public readTranscript(filePath: string): Array<Record<string, unknown>> {
    const entries: any[] = [];
    for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
      try {
        const entry = JSON.parse(line);
        if (entry.type !== 'session') entries.push(entry);
      } catch { /* An active terminal may have an unfinished final line. */ }
    }
    return SessionIndex.projectTranscript(entries);
  }

  public static projectTranscript(entries: any[]): Array<Record<string, unknown>> {
    const byId = new Map(entries.filter((e) => e.id).map((e) => [e.id, e]));
    const branch: any[] = [];
    const visited = new Set<string>();
    let cursor = entries.at(-1);
    while (cursor && cursor.id && !visited.has(cursor.id)) {
      visited.add(cursor.id);
      branch.unshift(cursor);
      cursor = byId.get(cursor.parentId);
    }
    return (branch.length ? branch : entries)
      .filter((entry) => (entry.type === 'message' || entry.role) && (entry.message || entry).role !== 'system')
      .map((entry) => ({ ...(entry.message || entry), id: entry.id }));
  }

  private parseSessionFile(
    sessionId: string,
    filePath: string,
    stat: fs.Stats,
    dirName: string
  ): SessionSummary | null {
    let cwd = process.cwd();
    let name: string | undefined = sessionId;
    let messageCount = 0;
    let lastMessagePreview: string | undefined;

    try {
      // Skip test/temporary projects before reading entire transcripts.
      const fd = fs.openSync(filePath, 'r');
      const headerBuffer = Buffer.alloc(16 * 1024);
      let headerBytes: number;
      try { headerBytes = fs.readSync(fd, headerBuffer, 0, headerBuffer.length, 0); }
      finally { fs.closeSync(fd); }
      const firstLine = headerBuffer.subarray(0, headerBytes).toString('utf8').split('\n', 1)[0];
      try {
        const header = JSON.parse(firstLine);
        if (header.type === 'session' && header.cwd && isTemporarySessionCwd(header.cwd)) return null;
      } catch { /* Legacy or incomplete headers use the normal parser below. */ }

      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n').filter((l) => l.trim().length > 0);
      for (const line of lines) {
        try {
          const entry = JSON.parse(line);
          if (entry.type === 'session') {
            if (entry.id) sessionId = entry.id;
            if (entry.cwd) cwd = entry.cwd;
          }
          if (entry.type === 'session_info') name = entry.name;
          if (entry.sessionName) name = entry.sessionName;
          if (entry.type === 'message' || entry.role) {
            const message = entry.message || entry;
            if (message.role === 'system') continue;
            messageCount++;
            let text = typeof message.content === 'string' ? message.content :
              (Array.isArray(message.content) ? message.content
                .filter((block: any) => block.type === 'text')
                .map((block: any) => block.text || '').join('') : '');
            if (!text && message.role === 'bashExecution') {
              text = message.command ? `!${message.command}` : (message.output || '');
            }
            if (!text && (message.role === 'branchSummary' || message.role === 'compactionSummary')) {
              text = message.summary || '';
            }
            if (text) lastMessagePreview = text.slice(0, 100);
          }
        } catch {}
      }
    } catch {}

    if (isTemporarySessionCwd(cwd)) return null;

    return {
      id: sessionId,
      name,
      cwd,
      gitRoot: null,
      sessionFile: filePath,
      createdAt: stat.birthtimeMs || stat.mtimeMs,
      lastActivityAt: stat.mtimeMs,
      sizeBytes: stat.size,
      messageCount,
      lastMessagePreview,
      isActive: false
    };
  }
}

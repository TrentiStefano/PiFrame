import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { getPiCrustBaseDir } from '../config/config.js';

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
  private cache = new Map<string, { mtime: number; summary: SessionSummary }>();

  constructor() {
    this.cachePath = path.join(getPiCrustBaseDir(), 'index.json');
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
      const list = Array.from(this.cache.values());
      const temp = `${this.cachePath}.tmp.${Date.now()}`;
      fs.writeFileSync(temp, JSON.stringify(list, null, 2), 'utf8');
      fs.renameSync(temp, this.cachePath);
    } catch {}
  }

  /**
   * Scans ~/.pi/agent/sessions/ strictly in read-only mode to index existing Pi sessions.
   */
  public async scan(activeSessionIds = new Set<string>()): Promise<SessionSummary[]> {
    const piSessionsDir = path.join(os.homedir(), '.pi', 'agent', 'sessions');
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
        if (!stat.isDirectory()) continue;

        const sessionFiles = fs.readdirSync(fullCwdDirPath);
        for (const sFile of sessionFiles) {
          if (!sFile.endsWith('.json') && !sFile.endsWith('.jsonl')) continue;

          const fullFilePath = path.join(fullCwdDirPath, sFile);
          let fileStat: fs.Stats;
          try {
            fileStat = fs.statSync(fullFilePath);
          } catch {
            continue;
          }

          const sessionId = path.basename(sFile, path.extname(sFile));
          const cached = this.cache.get(sessionId);

          if (cached && cached.mtime === fileStat.mtimeMs) {
            summaries.push({
              ...cached.summary,
              isActive: activeSessionIds.has(sessionId)
            });
            continue;
          }

          // Inspect session file preview
          const summary = this.parseSessionFile(sessionId, fullFilePath, fileStat, cwdDir);
          this.cache.set(sessionId, { mtime: fileStat.mtimeMs, summary });
          summaries.push({
            ...summary,
            isActive: activeSessionIds.has(sessionId)
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

  private parseSessionFile(
    sessionId: string,
    filePath: string,
    stat: fs.Stats,
    dirName: string
  ): SessionSummary {
    let cwd = process.cwd();
    let name: string | undefined = sessionId;
    let messageCount = 0;
    let lastMessagePreview: string | undefined;

    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n').filter((l) => l.trim().length > 0);
      messageCount = lines.length;

      for (const line of lines) {
        try {
          const entry = JSON.parse(line);
          if (entry.cwd) cwd = entry.cwd;
          if (entry.sessionName || entry.name) name = entry.sessionName || entry.name;
          if (entry.type === 'message' || entry.role) {
            const text = typeof entry.content === 'string' ? entry.content : JSON.stringify(entry.content || '');
            lastMessagePreview = text.slice(0, 100);
          }
        } catch {}
      }
    } catch {}

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

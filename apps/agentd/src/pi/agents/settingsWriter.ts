import * as fs from 'node:fs';
import * as path from 'node:path';
import { withFileLock, type LockOptions, type LockHandle } from './lockfile.js';
import { ensureSubagentContextLimitExtension } from './subagentContextLimitExtension.js';
import type { PiAgentChange } from '@piframe/pcp-ts';

export interface SettingsWriterLockOptions extends LockOptions {
  hookAfterRead?: (filePath: string) => Promise<void> | void;
  renameFn?: (temp: string, target: string) => void;
  maxRetries?: number;
  backoffMs?: number;
  lockHandle?: LockHandle;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function readSettingsFile(filePath: string): Record<string, any> {
  if (!fs.existsSync(filePath)) {
    return {};
  }
  let content: string;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (err: any) {
    const error = new Error(`Cannot read ${path.basename(filePath)}: ${err?.message}`);
    throw Object.assign(error, { code: 'AGENTS_CONFIG_UNREADABLE' });
  }

  // Strip UTF-8 BOM if present
  if (content.charCodeAt(0) === 0xFEFF) {
    content = content.slice(1);
  }

  try {
    const parsed = JSON.parse(content);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('Not a valid JSON object');
    }
    return parsed;
  } catch (parseErr: any) {
    const error = new Error(`Syntax error reading ${path.basename(filePath)}: not valid JSON`);
    throw Object.assign(error, { code: 'AGENTS_CONFIG_UNREADABLE' });
  }
}

/**
 * Retries renameSync on transient Windows filesystem errors (EPERM, EBUSY, EACCES)
 * up to maxRetries times with backoff.
 */
export async function renameWithRetry(
  tempFile: string,
  targetFile: string,
  options?: {
    maxRetries?: number;
    backoffMs?: number;
    renameFn?: (temp: string, target: string) => void;
  }
): Promise<void> {
  const maxRetries = options?.maxRetries ?? 10;
  const backoffMs = options?.backoffMs ?? 10;
  const doRename = options?.renameFn ?? fs.renameSync;

  let attempt = 0;
  while (true) {
    try {
      doRename(tempFile, targetFile);
      return;
    } catch (err: any) {
      attempt++;
      const isRetryable =
        err?.code === 'EPERM' || err?.code === 'EBUSY' || err?.code === 'EACCES';
      if (!isRetryable || attempt >= maxRetries) {
        throw err;
      }
      await sleep(backoffMs * attempt);
    }
  }
}

/**
 * Atomically writes JSON content to filePath with compatible locking, backup, mode preservation,
 * and Windows retry semantics. Unlinks temp file in finally if it still exists.
 */
export async function writeJsonAtomicallyWithBackup(
  filePath: string,
  content: any,
  options?: SettingsWriterLockOptions
): Promise<void> {
  const executeWrite = async (lock: LockHandle) => {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    let mode = 0o600;
    if (fs.existsSync(filePath)) {
      try {
        const stat = fs.statSync(filePath);
        mode = stat.mode & 0o777;
        const backupFile = `${filePath}.piframe-backup`;
        fs.copyFileSync(filePath, backupFile);
      } catch {
        // Fallback mode
      }
    }

    const tempFile = path.join(
      dir,
      `${path.basename(filePath)}.tmp.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}`
    );

    try {
      fs.writeFileSync(tempFile, JSON.stringify(content, null, 2) + '\n', {
        encoding: 'utf8',
        mode,
      });

      // Check lock ownership right before rename!
      lock.check();

      // Rename with retry on transient Windows locks
      await renameWithRetry(tempFile, filePath, {
        renameFn: options?.renameFn,
        maxRetries: options?.maxRetries,
        backoffMs: options?.backoffMs,
      });
    } finally {
      try {
        if (fs.existsSync(tempFile)) {
          fs.unlinkSync(tempFile);
        }
      } catch {
        // Ignore unlink error
      }
    }
  };

  if (options?.lockHandle) {
    await executeWrite(options.lockHandle);
  } else {
    await withFileLock(filePath, executeWrite, options);
  }
}

export interface SettingsApplyResult {
  settingsWritten: boolean;
  subagentsWritten: boolean;
  contextWritten: boolean;
}

/**
 * Applies a list of validated changes to settings.json, subagents.json, and subagent-context.json.
 * Holds lock across the ENTIRE read-modify-write cycle of each modified file.
 */
export async function applyAgentSettingsChanges(
  agentDir: string,
  piframeDir: string,
  changes: PiAgentChange[],
  lockOptions?: SettingsWriterLockOptions
): Promise<SettingsApplyResult> {
  const settingsPath = path.join(agentDir, 'settings.json');
  const tintinwebPath = path.join(agentDir, 'subagents.json');
  const contextPath = path.join(piframeDir, 'subagent-context.json');

  const touchesTintinweb = changes.some(
    (c) => c.kind === 'subagentDefaults' && c.fallbackAgent !== undefined
  );
  const touchesContext = changes.some(
    (c) => c.kind === 'agent' && c.contextLimit !== undefined
  );
  const touchesSettings = changes.some(
    (c) =>
      c.kind === 'agent' ||
      c.kind === 'sessionDefaults' ||
      (c.kind === 'subagentDefaults' &&
        (c.model !== undefined || c.thinking !== undefined))
  );

  // Pre-validate readability of all touched files (fail closed before modifying anything)
  const affectedPaths: string[] = [];
  if (touchesSettings) affectedPaths.push(settingsPath);
  if (touchesTintinweb) affectedPaths.push(tintinwebPath);
  if (touchesContext) affectedPaths.push(contextPath);

  for (const fp of affectedPaths) {
    if (fs.existsSync(fp)) {
      readSettingsFile(fp);
    }
  }

  // Lazy path for context limit extension
  let extensionPath: string | null = null;
  const getExtensionPath = () => {
    if (!extensionPath) {
      extensionPath = ensureSubagentContextLimitExtension(piframeDir);
    }
    return extensionPath;
  };

  let settingsModified = false;
  let tintinwebModified = false;
  let contextModified = false;

  // 1. Update subagent-context.json if affected (entire read-modify-write under lock)
  if (touchesContext) {
    contextModified = await withFileLock(
      contextPath,
      async (lock) => {
        const contextConfig = readSettingsFile(contextPath);
        if (lockOptions?.hookAfterRead) {
          await lockOptions.hookAfterRead(contextPath);
        }

        let modified = false;
        for (const change of changes) {
          if (change.kind === 'agent' && change.contextLimit !== undefined) {
            const name = change.name;
            if (change.contextLimit === null) {
              if (name in contextConfig) {
                delete contextConfig[name];
                modified = true;
              }
            } else {
              contextConfig[name] = change.contextLimit;
              modified = true;
            }
          }
        }

        if (modified) {
          await writeJsonAtomicallyWithBackup(contextPath, contextConfig, {
            ...lockOptions,
            lockHandle: lock,
          });
          return true;
        }
        return false;
      },
      lockOptions
    );
  }

  // 2. Update settings.json if affected (entire read-modify-write under lock)
  if (touchesSettings) {
    settingsModified = await withFileLock(
      settingsPath,
      async (lock) => {
        const settings = readSettingsFile(settingsPath);
        if (lockOptions?.hookAfterRead) {
          await lockOptions.hookAfterRead(settingsPath);
        }

        let modified = false;

        for (const change of changes) {
          if (change.kind === 'agent') {
            const name = change.name;

            // Handle contextLimit extension in settings.subagents
            if (change.contextLimit !== undefined) {
              if (change.contextLimit === null) {
                const currentOverrides = settings.subagents?.agentOverrides?.[name];
                if (Array.isArray(currentOverrides?.subagentOnlyExtensions)) {
                  const ext = getExtensionPath();
                  const filtered = currentOverrides.subagentOnlyExtensions.filter(
                    (p: string) => p !== ext
                  );
                  if (filtered.length !== currentOverrides.subagentOnlyExtensions.length) {
                    modified = true;
                    if (filtered.length === 0) {
                      delete currentOverrides.subagentOnlyExtensions;
                    } else {
                      currentOverrides.subagentOnlyExtensions = filtered;
                    }
                  }
                }
              } else {
                const ext = getExtensionPath();
                if (!settings.subagents) settings.subagents = {};
                if (!settings.subagents.agentOverrides) settings.subagents.agentOverrides = {};
                if (!settings.subagents.agentOverrides[name]) settings.subagents.agentOverrides[name] = {};
                const current = settings.subagents.agentOverrides[name];
                const exts = Array.isArray(current.subagentOnlyExtensions)
                  ? current.subagentOnlyExtensions
                  : [];
                if (!exts.includes(ext)) {
                  current.subagentOnlyExtensions = [...exts, ext];
                  modified = true;
                }
              }
            }

            // Handle model
            if (change.model !== undefined) {
              modified = true;
              if (!settings.subagents) settings.subagents = {};
              if (!settings.subagents.agentOverrides) settings.subagents.agentOverrides = {};
              if (!settings.subagents.agentOverrides[name]) settings.subagents.agentOverrides[name] = {};

              if (change.model === null) {
                delete settings.subagents.agentOverrides[name].model;
              } else {
                settings.subagents.agentOverrides[name].model = change.model;
              }
            }

            // Handle thinking
            if (change.thinking !== undefined) {
              modified = true;
              if (!settings.subagents) settings.subagents = {};
              if (!settings.subagents.agentOverrides) settings.subagents.agentOverrides = {};
              if (!settings.subagents.agentOverrides[name]) settings.subagents.agentOverrides[name] = {};

              if (change.thinking === null) {
                delete settings.subagents.agentOverrides[name].thinking;
              } else {
                settings.subagents.agentOverrides[name].thinking = change.thinking;
              }
            }

            // Clean up empty override objects
            if (settings.subagents?.agentOverrides?.[name]) {
              if (Object.keys(settings.subagents.agentOverrides[name]).length === 0) {
                delete settings.subagents.agentOverrides[name];
                if (Object.keys(settings.subagents.agentOverrides).length === 0) {
                  delete settings.subagents.agentOverrides;
                }
              }
            }
          } else if (change.kind === 'subagentDefaults') {
            if (change.model !== undefined) {
              modified = true;
              if (!settings.subagents) settings.subagents = {};
              if (change.model === null) {
                delete settings.subagents.defaultModel;
              } else {
                settings.subagents.defaultModel = change.model;
              }
            }

            if (change.thinking !== undefined) {
              modified = true;
              if (!settings.subagents) settings.subagents = {};
              if (change.thinking === null) {
                delete settings.subagents.defaultThinking;
              } else {
                settings.subagents.defaultThinking = change.thinking;
              }
            }

            // Clean up empty subagents object
            if (settings.subagents && Object.keys(settings.subagents).length === 0) {
              delete settings.subagents;
            }
          } else if (change.kind === 'sessionDefaults') {
            if (change.model !== undefined) {
              modified = true;
              if (change.model === null) {
                delete settings.defaultProvider;
                delete settings.defaultModel;
              } else {
                const slashIdx = change.model.indexOf('/');
                if (slashIdx !== -1) {
                  settings.defaultProvider = change.model.slice(0, slashIdx);
                  settings.defaultModel = change.model.slice(slashIdx + 1);
                } else {
                  settings.defaultModel = change.model;
                }
              }
            }

            if (change.thinking !== undefined) {
              modified = true;
              if (change.thinking === null) {
                delete settings.defaultThinkingLevel;
              } else {
                settings.defaultThinkingLevel = change.thinking;
              }
            }
          }
        }

        if (modified) {
          await writeJsonAtomicallyWithBackup(settingsPath, settings, {
            ...lockOptions,
            lockHandle: lock,
          });
          return true;
        }
        return false;
      },
      lockOptions
    );
  }

  // 3. Update subagents.json if affected (entire read-modify-write under lock)
  if (touchesTintinweb) {
    tintinwebModified = await withFileLock(
      tintinwebPath,
      async (lock) => {
        const tintinwebConfig = readSettingsFile(tintinwebPath);
        if (lockOptions?.hookAfterRead) {
          await lockOptions.hookAfterRead(tintinwebPath);
        }

        let modified = false;
        for (const change of changes) {
          if (change.kind === 'subagentDefaults' && change.fallbackAgent !== undefined) {
            if (change.fallbackAgent === null) {
              if ('fallbackSubagent' in tintinwebConfig) {
                delete tintinwebConfig.fallbackSubagent;
                modified = true;
              }
            } else {
              tintinwebConfig.fallbackSubagent = change.fallbackAgent;
              modified = true;
            }
          }
        }

        if (modified) {
          await writeJsonAtomicallyWithBackup(tintinwebPath, tintinwebConfig, {
            ...lockOptions,
            lockHandle: lock,
          });
          return true;
        }
        return false;
      },
      lockOptions
    );
  }

  return {
    settingsWritten: settingsModified,
    subagentsWritten: tintinwebModified,
    contextWritten: contextModified,
  };
}

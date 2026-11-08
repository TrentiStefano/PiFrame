import * as path from 'node:path';
import * as os from 'node:os';
import type {
  PiAgentsGetResult,
  PiAgentInfo,
  PiSubagentDefaults,
  PiSessionDefaults,
  PiAvailableModel,
  PiAgentChange,
} from '@piframe/pcp-ts';
import { getPiFrameBaseDir } from '../../config/config.js';
import { readSettingsFile, applyAgentSettingsChanges } from './settingsWriter.js';
import { detectSubagentPackages, discoverAgents } from './agentDiscovery.js';
import { readSubagentContextLimits } from './subagentContextLimitExtension.js';
import type { LockOptions } from './lockfile.js';

export const THINKING_LEVELS = [
  'off',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

export interface AgentsServiceOptions {
  agentDir?: string;
  piframeDir?: string;
  getAvailableModels?: () => Promise<{ models: PiAvailableModel[]; warning?: string }>;
  lockOptions?: LockOptions;
}

export class AgentsService {
  private agentDir: string;
  private piframeDir: string;
  private getAvailableModelsFn?: () => Promise<{ models: PiAvailableModel[]; warning?: string }>;
  private lockOptions?: LockOptions;
  private writeQueue = Promise.resolve();

  constructor(opts: AgentsServiceOptions = {}) {
    this.agentDir =
      opts.agentDir ||
      process.env.PI_CODING_AGENT_DIR ||
      path.join(os.homedir(), '.pi', 'agent');
    this.piframeDir = opts.piframeDir || getPiFrameBaseDir();
    this.getAvailableModelsFn = opts.getAvailableModels;
    this.lockOptions = opts.lockOptions;
  }

  public getAgentDir(): string {
    return this.agentDir;
  }

  public getPiFrameDir(): string {
    return this.piframeDir;
  }

  private async fetchAvailableModels(): Promise<{ models: PiAvailableModel[]; warning?: string }> {
    if (this.getAvailableModelsFn) {
      try {
        return await this.getAvailableModelsFn();
      } catch (err: any) {
        return {
          models: [],
          warning: `Failed to query available models from Pi: ${err?.message || 'unknown error'}`,
        };
      }
    }
    return { models: [], warning: 'No Pi connection available to query available models' };
  }

  public async getAgents(cwd?: string): Promise<PiAgentsGetResult> {
    const settingsPath = path.join(this.agentDir, 'settings.json');
    const tintinwebPath = path.join(this.agentDir, 'subagents.json');

    const settings = readSettingsFile(settingsPath);
    const tintinwebConfig = readSettingsFile(tintinwebPath);
    const contextLimits = readSubagentContextLimits(this.piframeDir);

    const packageDetection = detectSubagentPackages(this.agentDir, settings);
    const discoveredRaw = discoverAgents(this.agentDir, packageDetection, cwd);

    const { models: availableModels, warning: modelsWarning } = await this.fetchAvailableModels();
    const warnings: string[] = [];
    if (modelsWarning) {
      warnings.push(modelsWarning);
    }

    const isPiSubagentsInstalled = packageDetection.packages.some(
      (p) => p.id === 'pi-subagents' && p.installed
    );
    const isTintinwebInstalled = packageDetection.packages.some(
      (p) => p.id === '@tintinweb/pi-subagents' && p.installed
    );

    if (!isPiSubagentsInstalled && !isTintinwebInstalled) {
      warnings.push('No subagent package installed');
    }

    const modelMap = new Map<string, PiAvailableModel>();
    for (const m of availableModels) {
      modelMap.set(m.id, m);
    }

    const checkModelAvailable = (modelStr: string | null): boolean | null => {
      if (!modelStr) return null;
      if (availableModels.length === 0) return null;
      const base = modelStr.split(':')[0];
      return modelMap.has(base) || availableModels.some((m) => m.id === base || m.id === modelStr);
    };

    // Build agent list with effective values
    const agents: PiAgentInfo[] = discoveredRaw.map((agent) => {
      const overrides = settings.subagents?.agentOverrides?.[agent.name];

      // Model resolution
      let effectiveModel: string | null = null;
      let modelOrigin: 'override' | 'frontmatter' | 'default' | 'none' = 'none';

      if (typeof overrides?.model === 'string' && overrides.model.trim()) {
        effectiveModel = overrides.model.trim();
        modelOrigin = 'override';
      } else if (agent.frontmatterModel) {
        effectiveModel = agent.frontmatterModel;
        modelOrigin = 'frontmatter';
      } else if (typeof settings.subagents?.defaultModel === 'string' && settings.subagents.defaultModel.trim()) {
        effectiveModel = settings.subagents.defaultModel.trim();
        modelOrigin = 'default';
      }

      // Thinking resolution
      let effectiveThinking: string | null = null;
      let thinkingOrigin: 'override' | 'frontmatter' | 'default' | 'none' = 'none';

      if (typeof overrides?.thinking === 'string' && overrides.thinking.trim()) {
        effectiveThinking = overrides.thinking.trim();
        thinkingOrigin = 'override';
      } else if (agent.frontmatterThinking) {
        effectiveThinking = agent.frontmatterThinking;
        thinkingOrigin = 'frontmatter';
      } else if (typeof settings.subagents?.defaultThinking === 'string' && settings.subagents.defaultThinking.trim()) {
        effectiveThinking = settings.subagents.defaultThinking.trim();
        thinkingOrigin = 'default';
      }

      // Context resolution
      const limit = contextLimits[agent.name] ?? null;
      const baseModel = effectiveModel ? effectiveModel.split(':')[0] : null;
      const foundModel = baseModel ? (modelMap.get(baseModel) ?? availableModels.find((m) => m.id === baseModel)) : null;

      const supported = !!(foundModel && foundModel.tiers && foundModel.tiers.length > 0);
      const modelContextWindow = foundModel?.contextWindow ?? null;
      const options = supported && foundModel
        ? Array.from(new Set([...foundModel.tiers, foundModel.contextWindow])).sort((a, b) => a - b)
        : [];

      return {
        name: agent.name,
        aliases: agent.aliases,
        package: agent.package,
        source: agent.source,
        description: agent.description,
        editable: agent.editable,
        readOnlyReason: agent.readOnlyReason,
        model: {
          effective: effectiveModel,
          origin: modelOrigin,
          available: checkModelAvailable(effectiveModel),
        },
        thinking: {
          effective: effectiveThinking,
          origin: thinkingOrigin,
        },
        context: {
          supported,
          limit,
          options,
          modelContextWindow,
        },
      };
    });

    // Subagent defaults
    let subagentDefaults: PiSubagentDefaults;
    if (isPiSubagentsInstalled) {
      const defModel =
        typeof settings.subagents?.defaultModel === 'string' && settings.subagents.defaultModel.trim()
          ? settings.subagents.defaultModel.trim()
          : null;
      const defThinking =
        typeof settings.subagents?.defaultThinking === 'string' && settings.subagents.defaultThinking.trim()
          ? settings.subagents.defaultThinking.trim()
          : null;
      subagentDefaults = {
        package: 'pi-subagents',
        model: defModel,
        thinking: defThinking,
        modelAvailable: checkModelAvailable(defModel),
        fallbackAgent: null,
      };
    } else if (isTintinwebInstalled) {
      const fallback =
        typeof tintinwebConfig.fallbackSubagent === 'string' && tintinwebConfig.fallbackSubagent.trim()
          ? tintinwebConfig.fallbackSubagent.trim()
          : null;
      subagentDefaults = {
        package: '@tintinweb/pi-subagents',
        model: null,
        thinking: null,
        modelAvailable: null,
        fallbackAgent: fallback,
      };
    } else {
      subagentDefaults = {
        package: null,
        model: null,
        thinking: null,
        modelAvailable: null,
        fallbackAgent: null,
      };
    }

    // Session defaults
    const sessProvider =
      typeof settings.defaultProvider === 'string' && settings.defaultProvider.trim()
        ? settings.defaultProvider.trim()
        : null;
    let sessModel: string | null = null;
    if (typeof settings.defaultModel === 'string' && settings.defaultModel.trim()) {
      const raw = settings.defaultModel.trim();
      if (sessProvider && !raw.includes('/')) {
        sessModel = `${sessProvider}/${raw}`;
      } else {
        sessModel = raw;
      }
    }
    const sessThinking =
      typeof settings.defaultThinkingLevel === 'string' && settings.defaultThinkingLevel.trim()
        ? settings.defaultThinkingLevel.trim()
        : null;

    const sessionDefaults: PiSessionDefaults = {
      provider: sessProvider,
      model: sessModel,
      thinking: sessThinking,
      modelAvailable: checkModelAvailable(sessModel),
    };

    return {
      packages: packageDetection.packages,
      agents,
      subagentDefaults,
      sessionDefaults,
      thinkingLevels: THINKING_LEVELS,
      availableModels,
      warnings,
    };
  }

  public async updateAgents(changes: PiAgentChange[], cwd?: string): Promise<PiAgentsGetResult> {
    // Single in-process queue for serialized writes
    const run = async (): Promise<PiAgentsGetResult> => {
      // 1. Get current state for validation
      const current = await this.getAgents(cwd);
      const isPiSubagentsInstalled = current.packages.some(
        (p) => p.id === 'pi-subagents' && p.installed
      );
      const isTintinwebInstalled = current.packages.some(
        (p) => p.id === '@tintinweb/pi-subagents' && p.installed
      );

      const agentMap = new Map<string, PiAgentInfo>();
      for (const ag of current.agents) {
        agentMap.set(ag.name, ag);
      }

      const availableModelMap = new Map<string, PiAvailableModel>();
      for (const m of current.availableModels) {
        availableModelMap.set(m.id, m);
      }

      // Build alias-to-canonical lookup map
      const aliasToCanonical = new Map<string, string>();
      for (const ag of current.agents) {
        aliasToCanonical.set(ag.name, ag.name);
        if (ag.aliases) {
          for (const alias of ag.aliases) {
            aliasToCanonical.set(alias, ag.name);
          }
        }
      }

      // Map change agent names to canonical names
      const resolvedChanges: PiAgentChange[] = changes.map((c) => {
        if (c.kind === 'agent') {
          const canonical = aliasToCanonical.get(c.name);
          if (canonical) {
            return { ...c, name: canonical };
          }
        }
        return c;
      });

      const validationErrors: Array<{ field: string; message: string }> = [];

      // Check package requirements
      const touchesSubagents = resolvedChanges.some(
        (c) => c.kind === 'agent' || c.kind === 'subagentDefaults'
      );
      if (touchesSubagents && !isPiSubagentsInstalled && !isTintinwebInstalled) {
        const err = new Error('No subagent package installed');
        throw Object.assign(err, { code: 'AGENTS_PACKAGE_NOT_INSTALLED' });
      }

      for (const change of resolvedChanges) {
        if (change.kind === 'agent') {
          const agent = agentMap.get(change.name);
          if (!agent) {
            validationErrors.push({
              field: 'name',
              message: `Unknown agent: ${change.name}`,
            });
            continue;
          }

          if (!agent.editable) {
            validationErrors.push({
              field: 'agent',
              message: `Agent "${change.name}" is not editable (${agent.readOnlyReason ?? 'read-only'})`,
            });
            continue;
          }

          // Validate model if given
          if (change.model !== undefined && change.model !== null) {
            const baseModel = change.model.split(':')[0];
            if (
              current.availableModels.length > 0 &&
              !availableModelMap.has(baseModel) &&
              !current.availableModels.some((m) => m.id === baseModel || m.id === change.model)
            ) {
              validationErrors.push({
                field: 'model',
                message: 'model not available with current credentials',
              });
            }
          }

          // Effective model for checking reasoning and tiers
          const effectiveModel =
            change.model !== undefined ? change.model : agent.model.effective;
          const baseModel = effectiveModel ? effectiveModel.split(':')[0] : null;
          const modelInfo = baseModel ? availableModelMap.get(baseModel) : null;

          // Validate thinking if given
          if (change.thinking !== undefined && change.thinking !== null) {
            if (!THINKING_LEVELS.includes(change.thinking)) {
              validationErrors.push({
                field: 'thinking',
                message: `Invalid thinking level: ${change.thinking}`,
              });
            } else if (modelInfo && modelInfo.reasoning === false && change.thinking !== 'off') {
              validationErrors.push({
                field: 'thinking',
                message: 'Thinking level must be "off" for models without reasoning support',
              });
            }
          }

          // Validate contextLimit if given
          if (change.contextLimit !== undefined && change.contextLimit !== null) {
            if (!modelInfo || !modelInfo.tiers || modelInfo.tiers.length === 0) {
              validationErrors.push({
                field: 'contextLimit',
                message: 'Context limit requires a model with pricing tiers',
              });
            } else {
              const allowedOptions = Array.from(
                new Set([...modelInfo.tiers, modelInfo.contextWindow])
              );
              if (!allowedOptions.includes(change.contextLimit)) {
                validationErrors.push({
                  field: 'contextLimit',
                  message: `Context limit must be one of [${allowedOptions.join(', ')}]`,
                });
              }
            }
          }
        } else if (change.kind === 'subagentDefaults') {
          // Validate model
          if (change.model !== undefined && change.model !== null) {
            const baseModel = change.model.split(':')[0];
            if (
              current.availableModels.length > 0 &&
              !availableModelMap.has(baseModel) &&
              !current.availableModels.some((m) => m.id === baseModel || m.id === change.model)
            ) {
              validationErrors.push({
                field: 'model',
                message: 'model not available with current credentials',
              });
            }
          }

          // Validate thinking
          if (change.thinking !== undefined && change.thinking !== null) {
            if (!THINKING_LEVELS.includes(change.thinking)) {
              validationErrors.push({
                field: 'thinking',
                message: `Invalid thinking level: ${change.thinking}`,
              });
            } else {
              const defModel =
                change.model !== undefined
                  ? change.model
                  : current.subagentDefaults.model;
              const baseModel = defModel ? defModel.split(':')[0] : null;
              const modelInfo = baseModel ? availableModelMap.get(baseModel) : null;
              if (modelInfo && modelInfo.reasoning === false && change.thinking !== 'off') {
                validationErrors.push({
                  field: 'thinking',
                  message: 'Thinking level must be "off" for models without reasoning support',
                });
              }
            }
          }

          // Validate fallbackAgent (tintinweb)
          if (change.fallbackAgent !== undefined && change.fallbackAgent !== null) {
            if (!isTintinwebInstalled) {
              validationErrors.push({
                field: 'fallbackAgent',
                message: 'tintinweb package is not installed',
              });
            } else {
              const tintinwebAgents = current.agents.filter(
                (a) => a.package === '@tintinweb/pi-subagents'
              );
              if (!tintinwebAgents.some((a) => a.name === change.fallbackAgent)) {
                validationErrors.push({
                  field: 'fallbackAgent',
                  message: `Fallback agent "${change.fallbackAgent}" does not exist in tintinweb package`,
                });
              }
            }
          }
        } else if (change.kind === 'sessionDefaults') {
          // Validate model
          if (change.model !== undefined && change.model !== null) {
            const slashIdx = change.model.indexOf('/');
            if (slashIdx <= 0 || slashIdx === change.model.length - 1) {
              validationErrors.push({
                field: 'model',
                message: "Session default model must be in 'provider/id' format",
              });
            } else {
              const baseModel = change.model.split(':')[0];
              if (
                current.availableModels.length > 0 &&
                !availableModelMap.has(baseModel) &&
                !current.availableModels.some((m) => m.id === baseModel || m.id === change.model)
              ) {
                validationErrors.push({
                  field: 'model',
                  message: 'model not available with current credentials',
                });
              }
            }
          }

          // Validate thinking
          if (change.thinking !== undefined && change.thinking !== null) {
            if (!THINKING_LEVELS.includes(change.thinking)) {
              validationErrors.push({
                field: 'thinking',
                message: `Invalid thinking level: ${change.thinking}`,
              });
            } else {
              const sessModel =
                change.model !== undefined
                  ? change.model
                  : current.sessionDefaults.model;
              const baseModel = sessModel ? sessModel.split(':')[0] : null;
              const modelInfo = baseModel ? availableModelMap.get(baseModel) : null;
              if (modelInfo && modelInfo.reasoning === false && change.thinking !== 'off') {
                validationErrors.push({
                  field: 'thinking',
                  message: 'Thinking level must be "off" for models without reasoning support',
                });
              }
            }
          }
        }
      }

      if (validationErrors.length > 0) {
        const error = new Error('Agent settings validation failed');
        throw Object.assign(error, {
          code: 'AGENTS_VALIDATION_FAILED',
          details: validationErrors,
        });
      }

      // 2. Apply updates
      await applyAgentSettingsChanges(
        this.agentDir,
        this.piframeDir,
        resolvedChanges,
        this.lockOptions
      );

      // 3. Return fresh state
      return await this.getAgents(cwd);
    };

    // Serialize in-process
    const nextPromise = this.writeQueue.then(run, run);
    this.writeQueue = nextPromise.then(() => {}, () => {});
    return nextPromise;
  }
}

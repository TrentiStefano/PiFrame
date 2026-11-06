import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import type {
  PiSubagentPackageInfo,
  PiSubagentPackageId,
} from '@piframe/pcp-ts';
import { parseFrontmatter } from './frontmatter.js';

export const BUILTIN_NICOBALION_NAMES = new Set([
  'advisor',
  'claude-code',
  'claude-code-writer',
  'codex-exec',
  'codex-exec-writer',
  'cursor-agent',
  'cursor-agent-writer',
  'delegate',
  'evidence-auditor',
  'oracle',
  'researcher',
  'reviewer',
  'scout',
  'worker',
]);

export const BUILTIN_TINTINWEB_NAMES = new Set([
  'general-purpose',
  'Explore',
  'Plan',
]);

export interface DiscoveredAgentRaw {
  name: string;
  aliases: string[];
  package: string | null;
  source: 'builtin' | 'user' | 'project' | 'package';
  description: string | null;
  editable: boolean;
  readOnlyReason: string | null;
  frontmatterModel: string | null;
  frontmatterThinking: string | null;
  filePath?: string;
}

export function displayPath(fullPath: string): string {
  const home = os.homedir();
  if (fullPath.startsWith(home)) {
    const rel = fullPath.slice(home.length).replace(/^[/\\]+/, '');
    return `~/${rel.replace(/\\/g, '/')}`;
  }
  return fullPath.replace(/\\/g, '/');
}

export interface PackageDetectionResult {
  packages: PiSubagentPackageInfo[];
  nicobailonDir: string | null;
  tintinwebDir: string | null;
}

/**
 * Detect subagent packages in settings.json and filesystem.
 */
export function detectSubagentPackages(
  agentDir: string,
  settings: Record<string, any> = {}
): PackageDetectionResult {
  const packagesList: PiSubagentPackageInfo[] = [];

  // Check pi-subagents (nicobailon)
  const nicobailonDefaultDir = path.join(agentDir, 'npm', 'node_modules', 'pi-subagents');
  let nicobailonDir: string | null = null;
  let nicobailonVersion: string | null = null;

  if (fs.existsSync(nicobailonDefaultDir)) {
    nicobailonDir = nicobailonDefaultDir;
  } else {
    // Check settings.packages entries
    const declared = Array.isArray(settings.packages) ? settings.packages : [];
    for (const entry of declared) {
      if (typeof entry === 'string') {
        if (entry.includes('pi-subagents') && !entry.includes('@tintinweb')) {
          if (fs.existsSync(entry)) {
            nicobailonDir = entry;
          }
        }
      }
    }
  }

  if (nicobailonDir) {
    try {
      const pkgJson = JSON.parse(
        fs.readFileSync(path.join(nicobailonDir, 'package.json'), 'utf8')
      );
      nicobailonVersion = typeof pkgJson.version === 'string' ? pkgJson.version : null;
    } catch {
      nicobailonVersion = null;
    }
  }

  packagesList.push({
    id: 'pi-subagents',
    version: nicobailonVersion,
    installed: nicobailonDir !== null,
    configFile: displayPath(path.join(agentDir, 'settings.json')),
  });

  // Check @tintinweb/pi-subagents
  const tintinwebDefaultDir = path.join(
    agentDir,
    'npm',
    'node_modules',
    '@tintinweb',
    'pi-subagents'
  );
  let tintinwebDir: string | null = null;
  let tintinwebVersion: string | null = null;

  if (fs.existsSync(tintinwebDefaultDir)) {
    tintinwebDir = tintinwebDefaultDir;
  } else {
    const declared = Array.isArray(settings.packages) ? settings.packages : [];
    for (const entry of declared) {
      if (typeof entry === 'string' && entry.includes('@tintinweb/pi-subagents')) {
        if (fs.existsSync(entry)) {
          tintinwebDir = entry;
        }
      }
    }
  }

  if (tintinwebDir) {
    try {
      const pkgJson = JSON.parse(
        fs.readFileSync(path.join(tintinwebDir, 'package.json'), 'utf8')
      );
      tintinwebVersion = typeof pkgJson.version === 'string' ? pkgJson.version : null;
    } catch {
      tintinwebVersion = null;
    }
  }

  packagesList.push({
    id: '@tintinweb/pi-subagents',
    version: tintinwebVersion,
    installed: tintinwebDir !== null,
    configFile: displayPath(path.join(agentDir, 'subagents.json')),
  });

  return {
    packages: packagesList,
    nicobailonDir,
    tintinwebDir,
  };
}

function isExternalCliRunner(frontmatter: Record<string, any>): boolean {
  if (!frontmatter || typeof frontmatter !== 'object') return false;
  const runner = frontmatter.runner;
  if (!runner) return false;
  if (typeof runner === 'string') return true;
  if (typeof runner === 'object') {
    if (runner.type === 'external-cli' || runner.adapter || runner.command) {
      return true;
    }
    return true;
  }
  return false;
}

function readAgentsFromDir(
  dir: string,
  source: 'builtin' | 'user' | 'project' | 'package',
  pkgId: string | null,
  isTintinweb = false
): DiscoveredAgentRaw[] {
  if (!fs.existsSync(dir)) return [];
  const entries: DiscoveredAgentRaw[] = [];

  try {
    const files = fs.readdirSync(dir);
    for (const file of files) {
      if (!file.endsWith('.md')) continue;
      const fullPath = path.join(dir, file);
      try {
        const content = fs.readFileSync(fullPath, 'utf8');
        const { frontmatter } = parseFrontmatter(content);
        const name = (typeof frontmatter.name === 'string' && frontmatter.name.trim())
          ? frontmatter.name.trim()
          : path.basename(file, '.md');
        const description = typeof frontmatter.description === 'string' ? frontmatter.description.trim() : null;
        const frontmatterModel = typeof frontmatter.model === 'string' ? frontmatter.model.trim() : null;
        const frontmatterThinking = typeof frontmatter.thinking === 'string' ? frontmatter.thinking.trim() : null;

        // Extract aliases
        const aliasSet = new Set<string>();
        const addAlias = (val: any) => {
          if (typeof val === 'string' && val.trim()) {
            aliasSet.add(val.trim());
          } else if (Array.isArray(val)) {
            for (const item of val) {
              if (typeof item === 'string' && item.trim()) {
                aliasSet.add(item.trim());
              }
            }
          }
        };
        addAlias(frontmatter.alias);
        addAlias(frontmatter.aliases);
        const aliases = Array.from(aliasSet);

        let effectiveSource = source;
        if (pkgId === 'pi-subagents') {
          effectiveSource = BUILTIN_NICOBALION_NAMES.has(name) ? 'builtin' : 'package';
        } else if (isTintinweb) {
          effectiveSource = BUILTIN_TINTINWEB_NAMES.has(name) ? 'builtin' : 'package';
        }

        let editable = true;
        let readOnlyReason: string | null = null;

        if (isTintinweb) {
          editable = false;
          readOnlyReason = 'tintinweb: edit agent file';
        } else if (source === 'project') {
          editable = false;
          readOnlyReason = 'project agent (read-only)';
        } else if (isExternalCliRunner(frontmatter)) {
          editable = false;
          readOnlyReason = 'external CLI runner';
        }

        entries.push({
          name,
          aliases,
          package: pkgId,
          source: effectiveSource,
          description,
          editable,
          readOnlyReason,
          frontmatterModel,
          frontmatterThinking,
          filePath: fullPath,
        });
      } catch {
        // Skip unreadable files
      }
    }
  } catch {
    // Directory unreadable
  }

  return entries;
}

const SOURCE_PRIORITY: Record<string, number> = {
  builtin: 0,
  package: 1,
  user: 2,
  project: 3,
};

/**
 * Discover all agent files from package, user, and project directories.
 */
export function discoverAgents(
  agentDir: string,
  packageDetection: PackageDetectionResult,
  cwd?: string
): DiscoveredAgentRaw[] {
  const rawList: DiscoveredAgentRaw[] = [];

  // 1. Nicobailon package agents
  if (packageDetection.nicobailonDir) {
    const agentsDir = path.join(packageDetection.nicobailonDir, 'agents');
    rawList.push(...readAgentsFromDir(agentsDir, 'builtin', 'pi-subagents'));
  }

  // 2. Tintinweb package agents
  if (packageDetection.tintinwebDir) {
    const agentsDir = path.join(packageDetection.tintinwebDir, 'agents');
    const tintinwebAgents = readAgentsFromDir(agentsDir, 'builtin', '@tintinweb/pi-subagents', true);
    if (tintinwebAgents.length > 0) {
      rawList.push(...tintinwebAgents);
    } else {
      // Synthesize default builtin tintinweb agents if no md files present
      for (const name of BUILTIN_TINTINWEB_NAMES) {
        rawList.push({
          name,
          aliases: [],
          package: '@tintinweb/pi-subagents',
          source: 'builtin',
          description: `Tintinweb ${name} subagent`,
          editable: false,
          readOnlyReason: 'tintinweb: edit agent file',
          frontmatterModel: null,
          frontmatterThinking: null,
        });
      }
    }
  }

  // 3. User agents (~/.pi/agent/agents/*.md)
  const userAgentsDir = path.join(agentDir, 'agents');
  rawList.push(...readAgentsFromDir(userAgentsDir, 'user', null));

  // 4. Project agents (<cwd>/.pi/agents/*.md)
  if (cwd) {
    const projectAgentsDir = path.join(cwd, '.pi', 'agents');
    rawList.push(...readAgentsFromDir(projectAgentsDir, 'project', null));
  }

  // Deduplicate: higher priority source wins (preserve/merge aliases)
  const agentMap = new Map<string, DiscoveredAgentRaw>();
  for (const agent of rawList) {
    const existing = agentMap.get(agent.name);
    if (!existing) {
      agentMap.set(agent.name, agent);
    } else {
      const existingPri = SOURCE_PRIORITY[existing.source] ?? 0;
      const currentPri = SOURCE_PRIORITY[agent.source] ?? 0;
      const mergedAliases = Array.from(new Set([...existing.aliases, ...agent.aliases]));
      if (currentPri >= existingPri) {
        agent.aliases = mergedAliases;
        agentMap.set(agent.name, agent);
      } else {
        existing.aliases = mergedAliases;
      }
    }
  }

  return Array.from(agentMap.values()).sort((a, b) => a.name.localeCompare(b.name));
}

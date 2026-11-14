import '../../domain/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/agents/agents_config_controller.dart';
import '../../data/agents/agents_config_model.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../ui/frame_snack_bar.dart';

String formatContextTier(int tokens, int? modelContextWindow) {
  String base;
  if (tokens >= 1000000) {
    final m = tokens / 1000000.0;
    final formatted = m.toStringAsFixed(2);
    final clean = formatted.endsWith('.00')
        ? formatted.substring(0, formatted.length - 3)
        : (formatted.endsWith('0')
            ? formatted.substring(0, formatted.length - 1)
            : formatted);
    base = '${clean}M';
  } else if (tokens >= 1000) {
    final k = (tokens / 1000.0).round();
    base = '${k}k';
  } else {
    base = tokens.toString();
  }
  if (modelContextWindow != null && tokens >= modelContextWindow) {
    return '$base (full)';
  }
  return base;
}

class AgentsSection extends ConsumerStatefulWidget {
  const AgentsSection({super.key});

  @override
  ConsumerState<AgentsSection> createState() => _AgentsSectionState();
}

class _AgentsSectionState extends ConsumerState<AgentsSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentsConfigControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(agentsConfigControllerProvider);
    final notifier = ref.read(agentsConfigControllerProvider.notifier);

    if (state.isLoading && state.config == null) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }

    final config = state.config ?? const PiAgentsConfig();
    final installedPackages =
        config.packages.where((p) => p.installed).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Header title & subtitle
              Text(
                strings.agentsTitle,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                strings.agentsSubtitle,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),

              // Remote read-only banner
              if (state.isReadOnlyRemote) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, color: tokens.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.agentsReadOnlyNotice,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Global scope note banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: tokens.info, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.agentsGlobalNote,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Package header chips or Empty State
              _buildPackageHeader(tokens, strings, installedPackages),
              const SizedBox(height: 16),

              // Warnings
              if (config.warnings.isNotEmpty) ...[
                _buildWarnings(tokens, strings, config.warnings),
                const SizedBox(height: 16),
              ],

              // Defaults for new sessions card
              _buildSessionDefaultsCard(tokens, strings, state, config, notifier),
              const SizedBox(height: 20),

              // Subagent defaults card (only if packages installed)
              if (installedPackages.isNotEmpty) ...[
                _buildSubagentDefaultsCard(
                    tokens, strings, state, config, notifier),
                const SizedBox(height: 20),
              ],

              // Discovered Agents table/list (only if packages installed and agents exist)
              if (installedPackages.isNotEmpty && config.agents.isNotEmpty) ...[
                _buildAgentsList(tokens, strings, state, config, notifier),
                const SizedBox(height: 20),
              ],

              // General error display if any
              if (state.errorMessage != null && !state.isReadOnlyRemote) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.danger),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: tokens.danger, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          describeError(state.errorMessage!, strings).summary,
                          style: TextStyle(
                            color: tokens.danger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),

        // Bottom Action Bar (Save / Discard)
        _buildBottomActionBar(tokens, strings, state, notifier),
      ],
    );
  }

  Widget _buildPackageHeader(
    FrameTokens tokens,
    AppStrings strings,
    List<PiSubagentPackageInfo> installedPackages,
  ) {
    if (installedPackages.isEmpty) {
      // Empty state explaining how to install (README packages) - no fake list!
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          children: [
            Icon(
              Icons.extension_off_outlined,
              color: tokens.textMuted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              strings.agentsNoPackagesTitle,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.agentsNoPackagesDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: tokens.accent, size: 18),
          const SizedBox(width: 10),
          Text(
            strings.agentsPackagesLabel,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: installedPackages.map((pkg) {
                final versionText =
                    pkg.version != null ? ' (v${pkg.version})' : '';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(tokens.radiusPill),
                    border: Border.all(color: tokens.borderStrong),
                  ),
                  child: Text(
                    '${pkg.id}$versionText',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarnings(
    FrameTokens tokens,
    AppStrings strings,
    List<String> warnings,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: tokens.warning, size: 18),
              const SizedBox(width: 8),
              Text(
                strings.agentsWarningsTitle,
                style: TextStyle(
                  color: tokens.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 2),
              child: Text(
                '• $w',
                style: TextStyle(color: tokens.textSecondary, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDefaultsCard(
    FrameTokens tokens,
    AppStrings strings,
    AgentsConfigState state,
    PiAgentsConfig config,
    AgentsConfigController notifier,
  ) {
    final effectiveModel = state.getEffectiveSessionDefaultModel();
    final effectiveThinking = state.getEffectiveSessionDefaultThinking();
    final modelError = state.getValidationError('model');
    final thinkingError = state.getValidationError('thinking');

    final selectedModelObj = config.availableModels.cast<PiAvailableModel?>().firstWhere(
          (m) => m?.id == effectiveModel,
          orElse: () => null,
        );
    final isReasoningDisabled =
        selectedModelObj != null && selectedModelObj.reasoning == false;
    final isModelUnavailable = effectiveModel != null &&
        (state.config?.sessionDefaults.modelAvailable == false ||
            (config.availableModels.isNotEmpty &&
                !config.availableModels.any((m) => m.id == effectiveModel)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.agentsSessionDefaultsTitle,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.agentsSessionDefaultsSubtitle,
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),

          // Session model dropdown
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.agentsDefaultModel,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildModelDropdown(
                      tokens: tokens,
                      strings: strings,
                      effectiveModel: effectiveModel,
                      availableModels: config.availableModels,
                      isUnavailable: isModelUnavailable,
                      enabled: !state.isReadOnlyRemote,
                      onChanged: (val) {
                        if (val != null) notifier.editSessionDefaultModel(val);
                      },
                    ),
                    if (modelError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          modelError,
                          style:
                              TextStyle(color: tokens.danger, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: strings.agentsResetField,
                child: IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  color: tokens.textMuted,
                  onPressed: !state.isReadOnlyRemote
                      ? () => notifier.resetSessionDefaultModel()
                      : null,
                ),
              ),
              const SizedBox(width: 16),

              // Session thinking dropdown
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.agentsThinkingLevel,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildThinkingDropdown(
                      tokens: tokens,
                      effectiveThinking: effectiveThinking,
                      thinkingLevels: config.thinkingLevels,
                      reasoningDisabled: isReasoningDisabled,
                      enabled: !state.isReadOnlyRemote,
                      onChanged: (val) {
                        if (val != null) {
                          notifier.editSessionDefaultThinking(val);
                        }
                      },
                    ),
                    if (thinkingError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          thinkingError,
                          style:
                              TextStyle(color: tokens.danger, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: strings.agentsResetField,
                child: IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  color: tokens.textMuted,
                  onPressed: !state.isReadOnlyRemote
                      ? () => notifier.resetSessionDefaultThinking()
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubagentDefaultsCard(
    FrameTokens tokens,
    AppStrings strings,
    AgentsConfigState state,
    PiAgentsConfig config,
    AgentsConfigController notifier,
  ) {
    final subPkg = config.subagentDefaults.package;
    final isTintinweb = subPkg == '@tintinweb/pi-subagents';

    final effectiveModel = state.getEffectiveSubagentDefaultModel();
    final effectiveThinking = state.getEffectiveSubagentDefaultThinking();
    final effectiveFallback = state.getEffectiveSubagentDefaultFallbackAgent();

    final modelError = state.getValidationError('model');
    final thinkingError = state.getValidationError('thinking');
    final fallbackError = state.getValidationError('fallbackAgent');

    final selectedModelObj = config.availableModels.cast<PiAvailableModel?>().firstWhere(
          (m) => m?.id == effectiveModel,
          orElse: () => null,
        );
    final isReasoningDisabled =
        selectedModelObj != null && selectedModelObj.reasoning == false;
    final isModelUnavailable = effectiveModel != null &&
        (state.config?.subagentDefaults.modelAvailable == false ||
            (config.availableModels.isNotEmpty &&
                !config.availableModels.any((m) => m.id == effectiveModel)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.agentsSubagentDefaultsTitle,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.agentsSubagentDefaultsSubtitle,
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),

          if (isTintinweb) ...[
            // Fallback agent for tintinweb
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.agentsFallbackAgent,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildFallbackAgentDropdown(
                        tokens: tokens,
                        effectiveFallback: effectiveFallback,
                        agents: config.agents
                            .where((a) => a.package == '@tintinweb/pi-subagents')
                            .toList(),
                        enabled: !state.isReadOnlyRemote,
                        onChanged: (val) {
                          if (val != null) {
                            notifier.editSubagentDefaultFallbackAgent(val);
                          }
                        },
                      ),
                      if (fallbackError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            fallbackError,
                            style:
                                TextStyle(color: tokens.danger, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: strings.agentsResetField,
                  child: IconButton(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    color: tokens.textMuted,
                    onPressed: !state.isReadOnlyRemote
                        ? () => notifier.resetSubagentDefaultFallbackAgent()
                        : null,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Default model + thinking (nicobailon / pi-subagents)
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.agentsDefaultModel,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildModelDropdown(
                        tokens: tokens,
                        strings: strings,
                        effectiveModel: effectiveModel,
                        availableModels: config.availableModels,
                        isUnavailable: isModelUnavailable,
                        enabled: !state.isReadOnlyRemote,
                        onChanged: (val) {
                          if (val != null) {
                            notifier.editSubagentDefaultModel(val);
                          }
                        },
                      ),
                      if (modelError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            modelError,
                            style:
                                TextStyle(color: tokens.danger, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: strings.agentsResetField,
                  child: IconButton(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    color: tokens.textMuted,
                    onPressed: !state.isReadOnlyRemote
                        ? () => notifier.resetSubagentDefaultModel()
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.agentsThinkingLevel,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildThinkingDropdown(
                        tokens: tokens,
                        effectiveThinking: effectiveThinking,
                        thinkingLevels: config.thinkingLevels,
                        reasoningDisabled: isReasoningDisabled,
                        enabled: !state.isReadOnlyRemote,
                        onChanged: (val) {
                          if (val != null) {
                            notifier.editSubagentDefaultThinking(val);
                          }
                        },
                      ),
                      if (thinkingError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            thinkingError,
                            style:
                                TextStyle(color: tokens.danger, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: strings.agentsResetField,
                  child: IconButton(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    color: tokens.textMuted,
                    onPressed: !state.isReadOnlyRemote
                        ? () => notifier.resetSubagentDefaultThinking()
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgentsList(
    FrameTokens tokens,
    AppStrings strings,
    AgentsConfigState state,
    PiAgentsConfig config,
    AgentsConfigController notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.agentsListTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strings.agentsListSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 12),
        ...config.agents.map((agent) {
          return _buildAgentRow(tokens, strings, state, config, agent, notifier);
        }),
      ],
    );
  }

  Widget _buildAgentRow(
    FrameTokens tokens,
    AppStrings strings,
    AgentsConfigState state,
    PiAgentsConfig config,
    PiAgentInfo agent,
    AgentsConfigController notifier,
  ) {
    final isEditable = agent.editable && !state.isReadOnlyRemote;
    final effectiveModel = state.getEffectiveAgentModel(agent);
    final modelOrigin = state.getEffectiveAgentModelOrigin(agent);
    final effectiveThinking = state.getEffectiveAgentThinking(agent);
    final effectiveContextLimit = state.getEffectiveAgentContextLimit(agent);

    final selectedModelObj = config.availableModels.cast<PiAvailableModel?>().firstWhere(
          (m) => m?.id == effectiveModel,
          orElse: () => null,
        );
    final isReasoningDisabled =
        selectedModelObj != null && selectedModelObj.reasoning == false;
    final isModelUnavailable = effectiveModel != null &&
        (agent.model.available == false ||
            (config.availableModels.isNotEmpty &&
                !config.availableModels.any((m) => m.id == effectiveModel)));

    final modelError = state.getValidationError('model', agentName: agent.name);
    final thinkingError =
        state.getValidationError('thinking', agentName: agent.name);
    final contextError =
        state.getValidationError('contextLimit', agentName: agent.name);

    final bool isContextSupported;
    final List<int> contextOptions;
    final int? modelContextWindow;

    if (selectedModelObj != null) {
      isContextSupported = selectedModelObj.tiers.isNotEmpty;
      if (isContextSupported) {
        contextOptions = <int>{
          ...selectedModelObj.tiers,
          if (selectedModelObj.contextWindow > 0)
            selectedModelObj.contextWindow,
        }.toList()
          ..sort();
        modelContextWindow = selectedModelObj.contextWindow > 0
            ? selectedModelObj.contextWindow
            : null;
      } else {
        contextOptions = const [];
        modelContextWindow = null;
      }
    } else {
      isContextSupported = agent.context.supported;
      contextOptions = agent.context.options;
      modelContextWindow = agent.context.modelContextWindow;
    }

    final modelControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.agentsTableHeaderModel,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius:
                    BorderRadius.circular(tokens.radiusPill),
                border: Border.all(
                  color: modelOrigin == 'override'
                      ? tokens.accent
                      : tokens.border,
                ),
              ),
              child: Text(
                modelOrigin,
                style: TextStyle(
                  color: modelOrigin == 'override'
                      ? tokens.accent
                      : tokens.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _buildModelDropdown(
                tokens: tokens,
                strings: strings,
                effectiveModel: effectiveModel,
                availableModels: config.availableModels,
                isUnavailable: isModelUnavailable,
                enabled: isEditable,
                onChanged: (val) {
                  if (val != null) {
                    notifier.editAgentModel(agent.name, val);
                  }
                },
              ),
            ),
            Tooltip(
              message: strings.agentsResetField,
              child: IconButton(
                icon: const Icon(Icons.restart_alt, size: 16),
                color: tokens.textMuted,
                onPressed: isEditable
                    ? () => notifier.resetAgentModel(agent.name)
                    : null,
              ),
            ),
          ],
        ),
        if (modelError != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              modelError,
              style: TextStyle(color: tokens.danger, fontSize: 10),
            ),
          ),
      ],
    );

    final thinkingControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.agentsTableHeaderThinking,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _buildThinkingDropdown(
                tokens: tokens,
                effectiveThinking: effectiveThinking,
                thinkingLevels: config.thinkingLevels,
                reasoningDisabled: isReasoningDisabled,
                enabled: isEditable,
                onChanged: (val) {
                  if (val != null) {
                    notifier.editAgentThinking(agent.name, val);
                  }
                },
              ),
            ),
            Tooltip(
              message: strings.agentsResetField,
              child: IconButton(
                icon: const Icon(Icons.restart_alt, size: 16),
                color: tokens.textMuted,
                onPressed: isEditable
                    ? () => notifier.resetAgentThinking(agent.name)
                    : null,
              ),
            ),
          ],
        ),
        if (thinkingError != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              thinkingError,
              style: TextStyle(color: tokens.danger, fontSize: 10),
            ),
          ),
      ],
    );

    final contextControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.agentsTableHeaderContext,
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        if (isContextSupported) ...[
          Row(
            children: [
              Expanded(
                child: _buildContextDropdown(
                  tokens: tokens,
                  effectiveLimit: effectiveContextLimit,
                  options: contextOptions,
                  modelContextWindow: modelContextWindow,
                  enabled: isEditable,
                  onChanged: (val) {
                    notifier.editAgentContextLimit(agent.name, val);
                  },
                ),
              ),
              Tooltip(
                message: strings.agentsResetField,
                child: IconButton(
                  icon: const Icon(Icons.restart_alt, size: 16),
                  color: tokens.textMuted,
                  onPressed: isEditable
                      ? () => notifier.resetAgentContextLimit(agent.name)
                      : null,
                ),
              ),
            ],
          ),
          if (contextError != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                contextError,
                style: TextStyle(color: tokens.danger, fontSize: 10),
              ),
            ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Tooltip(
              message: strings.agentsContextSingleTierTooltip,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.agentsNotAvailableShort,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.help_outline,
                      size: 13, color: tokens.textMuted),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    Widget cardContent = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isEditable
            ? tokens.surfaceElevated
            : tokens.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: isEditable ? tokens.border : tokens.border.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Agent Name + Source Badge + Aliases + ReadOnly Badge
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                agent.name,
                style: TextStyle(
                  color: isEditable ? tokens.textPrimary : tokens.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Source badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(tokens.radiusPill),
                  border: Border.all(color: tokens.borderStrong),
                ),
                child: Text(
                  agent.source,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (agent.aliases.isNotEmpty)
                Text(
                  agent.aliases.length == 1
                      ? 'alias: ${agent.aliases.first}'
                      : 'aliases: ${agent.aliases.join(', ')}',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (!agent.editable)
                Tooltip(
                  message: agent.readOnlyReason ?? 'Read-only',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: tokens.border.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(tokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 11, color: tokens.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          agent.readOnlyReason ?? 'read-only',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (agent.description != null && agent.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              agent.description!,
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),

          // Row 2: Responsive Controls (Model, Thinking, Context)
          LayoutBuilder(
            builder: (context, constraints) {
              final isStacked = constraints.maxWidth < 650;
              if (isStacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    modelControl,
                    const SizedBox(height: 10),
                    thinkingControl,
                    const SizedBox(height: 10),
                    contextControl,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: modelControl),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: thinkingControl),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: contextControl),
                ],
              );
            },
          ),
        ],
      ),
    );

    if (!agent.editable && agent.readOnlyReason != null) {
      return Tooltip(
        message: agent.readOnlyReason!,
        child: cardContent,
      );
    }
    return cardContent;
  }

  Widget _buildModelDropdown({
    required FrameTokens tokens,
    required AppStrings strings,
    required String? effectiveModel,
    required List<PiAvailableModel> availableModels,
    required bool isUnavailable,
    required bool enabled,
    required ValueChanged<String?> onChanged,
  }) {
    // Dropdowns only offer available models
    final items = availableModels.map((m) {
      return DropdownMenuItem<String>(
        value: m.id,
        child: Text(
          m.name.isNotEmpty ? m.name : m.id,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 12,
          ),
        ),
      );
    }).toList();

    // If effective model is not among available models, add placeholder display
    final valueInItems =
        availableModels.any((m) => m.id == effectiveModel);
    final displayValue = valueInItems ? effectiveModel : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: enabled ? tokens.surface : tokens.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: isUnavailable ? tokens.warning : tokens.border,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: displayValue,
              hint: Text(
                effectiveModel ?? '—',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isUnavailable ? tokens.warning : tokens.textMuted,
                  fontSize: 12,
                ),
              ),
              isExpanded: true,
              dropdownColor: tokens.surfaceElevated,
              items: items,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        if (isUnavailable) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 13, color: tokens.warning),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  strings.agentsModelUnavailableWarning,
                  style: TextStyle(color: tokens.warning, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildThinkingDropdown({
    required FrameTokens tokens,
    required String? effectiveThinking,
    required List<String> thinkingLevels,
    required bool reasoningDisabled,
    required bool enabled,
    required ValueChanged<String?> onChanged,
  }) {
    final levels = reasoningDisabled
        ? const ['off']
        : (thinkingLevels.isNotEmpty
            ? thinkingLevels
            : const ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']);

    final effectiveVal = reasoningDisabled ? 'off' : effectiveThinking;
    final valueInItems = levels.contains(effectiveVal);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled ? tokens.surface : tokens.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valueInItems ? effectiveVal : null,
          hint: Text(
            effectiveVal ?? '—',
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          isExpanded: true,
          dropdownColor: tokens.surfaceElevated,
          items: levels.map((lvl) {
            return DropdownMenuItem<String>(
              value: lvl,
              child: Text(
                ref.read(appStringsProvider).thinkingLevelLabel(lvl),
                style: TextStyle(color: tokens.textPrimary, fontSize: 12),
              ),
            );
          }).toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _buildContextDropdown({
    required FrameTokens tokens,
    required int? effectiveLimit,
    required List<int> options,
    required int? modelContextWindow,
    required bool enabled,
    required ValueChanged<int?> onChanged,
  }) {
    final items = options.map((opt) {
      final label = formatContextTier(opt, modelContextWindow);
      return DropdownMenuItem<int>(
        value: opt,
        child: Text(
          label,
          style: TextStyle(color: tokens.textPrimary, fontSize: 12),
        ),
      );
    }).toList();

    final valueInItems =
        effectiveLimit != null && options.contains(effectiveLimit);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled ? tokens.surface : tokens.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: valueInItems ? effectiveLimit : null,
          hint: Text(
            effectiveLimit != null
                ? formatContextTier(effectiveLimit, modelContextWindow)
                : '—',
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          isExpanded: true,
          dropdownColor: tokens.surfaceElevated,
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _buildFallbackAgentDropdown({
    required FrameTokens tokens,
    required String? effectiveFallback,
    required List<PiAgentInfo> agents,
    required bool enabled,
    required ValueChanged<String?> onChanged,
  }) {
    final items = agents.map((a) {
      return DropdownMenuItem<String>(
        value: a.name,
        child: Text(
          a.name,
          style: TextStyle(color: tokens.textPrimary, fontSize: 12),
        ),
      );
    }).toList();

    final valueInItems = agents.any((a) => a.name == effectiveFallback);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled ? tokens.surface : tokens.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valueInItems ? effectiveFallback : null,
          hint: Text(
            effectiveFallback ?? '—',
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          isExpanded: true,
          dropdownColor: tokens.surfaceElevated,
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(
    FrameTokens tokens,
    AppStrings strings,
    AgentsConfigState state,
    AgentsConfigController notifier,
  ) {
    final canSave = state.isDirty &&
        !state.isSaving &&
        !state.isLoading &&
        !state.isReadOnlyRemote;
    final canDiscard = state.isDirty && !state.isSaving && !state.isLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Discard button
          OutlinedButton(
            onPressed: canDiscard ? () => notifier.discardEdits() : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.textSecondary,
              side: BorderSide(
                color: canDiscard
                    ? tokens.borderStrong
                    : tokens.border.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(strings.agentsDiscard),
          ),
          const SizedBox(width: 12),

          // Save button
          FilledButton.icon(
            onPressed: canSave
                ? () async {
                    final ok = await notifier.save();
                    if (ok && mounted) {
                      FrameSnackBar.show(
                        context,
                        message: strings.agentsSaveSuccess,
                      );
                    }
                  }
                : null,
            icon: state.isSaving
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accentContrast,
                    ),
                  )
                : const Icon(Icons.check, size: 16),
            label: Text(
                state.isSaving ? strings.agentsSaving : strings.agentsSave),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.accentContrast,
              disabledBackgroundColor: tokens.accent.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

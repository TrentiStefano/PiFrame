import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_composer.dart';
import '../../domain/session/context_pricing_helper.dart';
import '../../domain/session/agent_status.dart';
import '../session_tree/session_tree_dialog.dart';
import '../workspace/repository_workspace.dart';
import 'context_window_selector.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/motion.dart';
import '../../ui/precision.dart';

/// Width of the context drawer. No layout token covers it yet.
const double _drawerWidth = 320;

class ContextPanel extends ConsumerStatefulWidget {
  final String sessionId;

  const ContextPanel({super.key, required this.sessionId});

  @override
  ConsumerState<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends ConsumerState<ContextPanel> {
  List<Map<String, dynamic>> _models = [];
  List<String> _thinkingLevels = [];
  bool _isLoadingParams = true;
  bool _isCompacting = false;
  double? _reserveDraft;
  bool _savingReserve = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadParams());
  }

  @override
  void didUpdateWidget(covariant ContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _models = [];
      _isLoadingParams = true;
      _reserveDraft = null;
      _savingReserve = false;
      unawaited(_loadParams());
    }
  }

  Future<void> _loadParams() async {
    final sessionId = widget.sessionId;
    final notifier = ref.read(sessionStateFamily(sessionId).notifier);
    await notifier.refreshDefaults();
    try {
      final result = await notifier.getAvailableModelsWithWarning();
      final levels = await notifier.getAvailableThinkingLevels();

      if (mounted && widget.sessionId == sessionId) {
        setState(() {
          _models = result.models.map((model) => Map<String, dynamic>.from(model)).toList();
          _thinkingLevels = levels.isNotEmpty ? levels : ['off', 'low', 'medium', 'high'];
          _isLoadingParams = false;
        });
        if (result.warning != null) {
          FrameSnackBar.show(context, message: result.warning!);
        }
      }
    } catch (error) {
      if (mounted && widget.sessionId == sessionId) {
        final strings = ref.read(appStringsProvider);
        setState(() => _isLoadingParams = false);
        FrameSnackBar.show(context, message: strings.modelsNotAvailable(error));
      }
    }
  }

  String _modelOptionValue(Map<String, dynamic> model) =>
      '${model['provider'] ?? ''}\u0000${model['id'] ?? model['name'] ?? ''}';

  String? _modelDropdownValue(String? currentModel, String? currentProvider, String? currentId) {
    if (_models.isEmpty) return null;
    final index = _models.indexWhere((model) {
      if (currentProvider != null && currentProvider.isNotEmpty && model['provider']?.toString() != currentProvider) {
        return false;
      }
      if (currentId != null) return model['id']?.toString() == currentId;
      return model['id']?.toString() == currentModel || model['name']?.toString() == currentModel;
    });
    return _modelOptionValue(_models[index < 0 ? 0 : index]);
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.actionFailed(error));
      }
      return false;
    }
  }

  Future<void> _saveReserve(double percent) async {
    if (_savingReserve || ref.read(contextPolicySavingProvider(widget.sessionId))) {
      return;
    }
    final sessionId = widget.sessionId;
    final saving = ref.read(contextPolicySavingProvider(sessionId).notifier);
    saving.state = true;
    setState(() => _savingReserve = true);
    try {
      await ref.read(sessionStateFamily(sessionId).notifier).setCompactionReservePercent(percent);
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        if (widget.sessionId == sessionId) {
          FrameSnackBar.show(context, message: strings.compactionMarginNotApplied(error));
        }
      }
    } finally {
      if (saving.mounted) saving.state = false;
      if (mounted && widget.sessionId == sessionId) {
        setState(() {
          _savingReserve = false;
          _reserveDraft = null;
        });
      }
    }
  }

  Future<void> _triggerCompaction() async {
    if (_isCompacting) return;
    setState(() => _isCompacting = true);

    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    Map<String, dynamic>? res;
    try {
      final result = await notifier.compact();
      res = (result?['data'] as Map<String, dynamic>?) ?? result;
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.compactionFailed(error));
      }
    } finally {
      if (mounted) setState(() => _isCompacting = false);
    }

    if (mounted && res != null) {
      final strings = ref.read(appStringsProvider);
      final tokensBefore = res['tokensBefore'] ?? '?';
      final tokensAfter = res['estimatedTokensAfter'] ?? res['tokensAfter'] ?? '?';
      final usage = res['usage'] as Map?;
      final usageCost = usage?['cost'];
      final cost = usageCost is Map ? '\$${usageCost['total']}' : '';

      await _closeDrawer();
      if (!mounted) return;
      await showFrameDialog<bool>(
        context: context,
        dialog: FrameDialog<bool>(
          title: strings.compactionCompletedTitle,
          body: Text(
            strings.compactionDialogContent(tokensBefore, tokensAfter, cost),
            style: FrameText.of(context).body.copyWith(color: context.tokens.textSecondary),
          ),
          actions: [
            FrameDialogAction<bool>(
              label: strings.compactionDismissAction,
              role: FrameDialogActionRole.primary,
              value: true,
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cloneSession() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    if (!await resolveDirtyRepository(context, ref, ref.read(activeSessionIdProvider))) {
      return;
    }
    try {
      final result = await client.cloneSession(widget.sessionId);
      if (!mounted) return;
      final data = (result['data'] as Map<String, dynamic>?) ?? result;
      final targetSessionId = (data['sessionId'] ?? data['id']) as String?;
      if (targetSessionId != null) {
        if (!await switchSessionSafely(context, ref, targetSessionId)) {
          return;
        }
        ref.invalidate(sessionListProvider);
      }
    } catch (error) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        FrameSnackBar.show(context, message: strings.duplicationFailed(error));
      }
    }
  }

  /// Closes the drawer this panel is shown in, if it is open, and waits for its
  /// exit so a dialog launched from the panel does not stack on top of it.
  Future<void> _closeDrawer() async {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold == null || !scaffold.isEndDrawerOpen) return;
    scaffold.closeEndDrawer();
    await Future<void>.delayed(FrameMotion.panelExit);
  }

  Future<void> _openTree() async {
    await _closeDrawer();
    if (!mounted) return;
    await SessionTreeDialog.show(context, sessionId: widget.sessionId);
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: text.label.copyWith(color: tokens.textSecondary)),
        const SizedBox(height: FrameSpace.x2),
        ...children,
      ],
    );
  }

  Widget _fieldBox(BuildContext context, Widget child) {
    final tokens = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: FrameSize.rowForm),
      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final title = ref.watch(sessionDisplayNameProvider(widget.sessionId));
    final currentModel = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.currentModel));
    final currentModelProvider = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.currentModelProvider));
    final currentModelId = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.currentModelId));
    final currentThinkingLevel = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.currentThinkingLevel));
    final usage = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.usage));
    final sessionStats = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.sessionStats));
    final readOnly = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.readOnly));
    final sessionBusy = ref.watch(
      sessionStateFamily(widget.sessionId).select(
        (s) =>
            s.isStreaming ||
            const {AgentStatus.retrying, AgentStatus.compacting, AgentStatus.awaitingUser}.contains(s.agentStatus),
      ),
    );
    final policySaving = ref.watch(contextPolicySavingProvider(widget.sessionId));
    final sessionNotifier = ref.read(sessionStateFamily(widget.sessionId).notifier);

    final currentThinking = currentThinkingLevel ?? 'medium';

    final contextUsage =
        (sessionStats?['contextUsage'] as Map<String, dynamic>?) ?? (usage?['contextUsage'] as Map<String, dynamic>?);
    final totalTokens = (contextUsage?['tokens'] as num?)?.toInt();
    final percent = (contextUsage?['percent'] as num?)?.toDouble();
    final autoCompaction = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.autoCompaction));

    final activeModelMap = _models.firstWhere(
      (model) => currentModelId != null
          ? model['id']?.toString() == currentModelId &&
                (currentModelProvider == null || model['provider']?.toString() == currentModelProvider)
          : model['name'] == currentModel || model['id'] == currentModel,
      orElse: () => const {},
    );
    final fullWindow = modelContextWindow(activeModelMap);
    final contextOverride = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.contextWindowOverride));
    final reservePercent = ref.watch(sessionStateFamily(widget.sessionId).select((s) => s.compactionReservePercent));
    final reserveValue = (_reserveDraft ?? reservePercent).clamp(0.5, 25).toDouble();
    final effectiveWindow = contextOverride ?? (contextUsage?['contextWindow'] as num?)?.toInt() ?? fullWindow ?? 0;
    final compactionThreshold = effectiveWindow > 0 ? usableContextWindow(effectiveWindow, reservePercent) : 0.0;
    final effectivePercent = effectiveWindow > 0 && totalTokens != null
        ? (totalTokens / effectiveWindow * 100.0)
        : percent;
    final sessionLocked = readOnly || sessionBusy || policySaving;

    final modelSection = _section(context, strings.contextModelSection, [
      _isLoadingParams
          ? SizedBox(
              height: FrameSize.rowForm,
              child: Center(
                child: FrameActivityIndicator(size: FrameSize.iconLg, strokeWidth: 2, color: tokens.accent),
              ),
            )
          : _models.isEmpty
          ? Text(
              currentModel == null ? strings.noModelEnabled : strings.modelListNotAvailable(currentModel),
              style: text.caption.copyWith(color: tokens.textMuted),
            )
          : _fieldBox(
              context,
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                  dropdownColor: tokens.surfaceElevated,
                  key: const ValueKey('context-model-dropdown'),
                  value: _modelDropdownValue(currentModel, currentModelProvider, currentModelId),
                  style: text.body.copyWith(color: tokens.textPrimary),
                  items: _models.map((model) {
                    final name = model['name'] as String? ?? model['id'] as String;
                    String? provider = model['provider']?.toString();
                    if ((provider == null || provider.isEmpty) && model['id'] is String) {
                      final id = model['id'] as String;
                      final slash = id.indexOf('/');
                      if (slash > 0) {
                        provider = id.substring(0, slash);
                      } else {
                        final lower = id.toLowerCase();
                        if (lower.startsWith('claude')) {
                          provider = 'anthropic';
                        } else if (lower.startsWith('gpt') ||
                            lower.startsWith('o1') ||
                            lower.startsWith('o3') ||
                            lower.startsWith('chatgpt')) {
                          provider = 'openai';
                        } else if (lower.startsWith('gemini')) {
                          provider = 'google';
                        } else if (lower.startsWith('mistral') || lower.startsWith('codestral')) {
                          provider = 'mistral';
                        } else if (lower.startsWith('deepseek')) {
                          provider = 'deepseek';
                        } else if (lower.startsWith('qwen')) {
                          provider = 'qwen';
                        } else if (lower.startsWith('llama')) {
                          provider = 'meta';
                        }
                      }
                    }
                    return DropdownMenuItem<String>(
                      value: _modelOptionValue(model),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: text.body.copyWith(color: tokens.textPrimary),
                          ),
                          if (provider != null && provider.isNotEmpty)
                            Text(
                              provider,
                              overflow: TextOverflow.ellipsis,
                              style: text.caption.copyWith(color: tokens.textMuted),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  selectedItemBuilder: (context) {
                    return _models.map((model) {
                      final name = model['name'] as String? ?? model['id'] as String;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: text.body.copyWith(color: tokens.textPrimary),
                        ),
                      );
                    }).toList();
                  },
                  onChanged: sessionLocked
                      ? null
                      : (newModel) {
                          if (newModel != null) {
                            final modelObj = _models.firstWhere(
                              (model) => _modelOptionValue(model) == newModel,
                              orElse: () => const <String, dynamic>{},
                            );
                            if (modelObj.isEmpty) return;
                            final provider = modelObj['provider']?.toString() ?? '';
                            final modelId = modelObj['id']?.toString() ?? newModel;
                            unawaited(_runAction(() => sessionNotifier.setModel(provider, modelId)));
                          }
                        },
                ),
              ),
            ),
      const SizedBox(height: FrameSpace.x4),
      Text(strings.thinkingLevelHeader, style: text.caption.copyWith(color: tokens.textSecondary)),
      const SizedBox(height: FrameSpace.x1),
      _fieldBox(
        context,
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            dropdownColor: tokens.surfaceElevated,
            value: _thinkingLevels.contains(currentThinking)
                ? currentThinking
                : (_thinkingLevels.isNotEmpty ? _thinkingLevels.first : 'off'),
            style: text.body.copyWith(color: tokens.textPrimary),
            items: _thinkingLevels.map((lvl) {
              return DropdownMenuItem<String>(
                value: lvl,
                child: Text(ref.read(appStringsProvider).thinkingLevelLabel(lvl)),
              );
            }).toList(),
            onChanged: sessionLocked
                ? null
                : (newLevel) {
                    if (newLevel != null) {
                      unawaited(_runAction(() => sessionNotifier.setThinkingLevel(newLevel)));
                    }
                  },
          ),
        ),
      ),
    ]);

    final contextSection = _section(context, strings.contextContextSection, [
      Text(strings.contextSizeHeader, style: text.caption.copyWith(color: tokens.textSecondary)),
      const SizedBox(height: FrameSpace.x1),
      ContextWindowSelector(sessionId: widget.sessionId, model: activeModelMap, readOnly: readOnly),
      const SizedBox(height: FrameSpace.x3),
      Text(strings.compactionMarginHeader, style: text.caption.copyWith(color: tokens.textSecondary)),
      Slider(
        key: const ValueKey('context-panel-compaction-reserve-slider'),
        activeColor: tokens.accent,
        thumbColor: tokens.accent,
        inactiveColor: tokens.border,
        min: 0.5,
        max: 25,
        divisions: 49,
        value: reserveValue,
        label: '${reserveValue.toStringAsFixed(1)}%',
        semanticFormatterCallback: (value) => '${value.toStringAsFixed(1)}%',
        onChanged: readOnly || sessionBusy || _savingReserve || policySaving
            ? null
            : (value) => setState(() => _reserveDraft = value),
        onChangeEnd: readOnly || sessionBusy || _savingReserve || policySaving ? null : _saveReserve,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(strings.compactionMarginStep, style: text.caption.copyWith(color: tokens.textMuted)),
          Text('${reserveValue.toStringAsFixed(1)}%', style: text.caption.copyWith(color: tokens.textMuted)),
        ],
      ),
      if (reservePercent < 0.5 || reservePercent > 25)
        Text(
          strings.compactionMarginOutOfRange(reservePercent.toStringAsFixed(1)),
          style: text.caption.copyWith(color: tokens.warning),
        ),
      const SizedBox(height: FrameSpace.x1),
      Text(
        !autoCompaction
            ? strings.autoCompactionDisabled
            : effectiveWindow > 0
            ? strings.compactionThresholdInfo(
                formatTokens(compactionThreshold.floor()),
                reservePercent.toStringAsFixed(1),
              )
            : strings.compactionMarginUnused,
        style: text.caption.copyWith(color: tokens.textMuted),
      ),
      const SizedBox(height: FrameSpace.x3),
      Text(strings.contextUsageHeader, style: text.caption.copyWith(color: tokens.textSecondary)),
      const SizedBox(height: FrameSpace.x2),
      if (effectivePercent != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: LinearProgressIndicator(
            value: (effectivePercent / 100.0).clamp(0.0, 1.0),
            backgroundColor: tokens.background,
            valueColor: AlwaysStoppedAnimation<Color>(
              effectivePercent > 80 ? tokens.danger : (effectivePercent > 60 ? tokens.warning : tokens.success),
            ),
            minHeight: FrameSpace.x2,
          ),
        ),
      const SizedBox(height: FrameSpace.x1),
      // With a percentage shown, the token count is only added when known,
      // so the text never says data is missing next to a value.
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (totalTokens != null)
            Text(
              strings.contextTokensUsage(totalTokens, formatTokens(effectiveWindow)),
              style: text.caption.copyWith(color: tokens.textMuted),
            )
          else if (effectivePercent == null)
            Text(strings.dataNotAvailable, style: text.caption.copyWith(color: tokens.textMuted))
          else
            const SizedBox.shrink(),
          if (effectivePercent != null)
            Text(
              '${effectivePercent.toStringAsFixed(1)} %',
              style: text.caption.copyWith(color: tokens.textMuted, fontWeight: FontWeight.bold),
            ),
        ],
      ),
      const SizedBox(height: FrameSpace.x3),
      // The one primary action of this section.
      PressFeedback(
        enabled: (_isCompacting || readOnly ? null : _triggerCompaction) != null,
        child: FilledButton.icon(
          key: const ValueKey('context-compact-action'),
          style: FilledButton.styleFrom(backgroundColor: tokens.accent, foregroundColor: tokens.surface),
          icon: _isCompacting
              ? SizedBox(
                  width: FrameSize.icon,
                  height: FrameSize.icon,
                  child: FrameActivityIndicator(size: FrameSize.iconLg, strokeWidth: 2, color: tokens.surface),
                )
              : const Icon(Icons.compress_outlined, size: FrameSize.icon),
          label: Text(_isCompacting ? strings.compactingLabel : strings.compactContextAction),
          onPressed: _isCompacting || readOnly ? null : _triggerCompaction,
        ),
      ),
    ]);

    final branchesSection = _section(context, strings.contextBranchesSection, [
      PressFeedback(
        child: OutlinedButton.icon(
          key: const ValueKey('context-duplicate-action'),
          style: OutlinedButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            side: BorderSide(color: tokens.border),
          ),
          icon: Icon(Icons.content_copy_outlined, size: FrameSize.icon, color: tokens.textSecondary),
          label: Text(strings.duplicateBranchAction),
          onPressed: _cloneSession,
        ),
      ),
      const SizedBox(height: FrameSpace.x2),
      PressFeedback(
        child: OutlinedButton.icon(
          key: const ValueKey('context-tree-action'),
          style: OutlinedButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            side: BorderSide(color: tokens.border),
          ),
          icon: Icon(Icons.account_tree_outlined, size: FrameSize.icon, color: tokens.textSecondary),
          label: Text(strings.branchTreeAction),
          onPressed: _openTree,
        ),
      ),
    ]);

    return Container(
      width: _drawerWidth,
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The single heading of the panel: the session title.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x4, vertical: FrameSpace.x3),
            decoration: BoxDecoration(
              color: tokens.displaySurface,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Semantics(
              header: true,
              child: Text(
                strings.contextDrawerHeading(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.heading.copyWith(color: tokens.displayText),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(FrameSpace.x4),
              children: [
                modelSection,
                const SizedBox(height: FrameSpace.x6),
                contextSection,
                const SizedBox(height: FrameSpace.x6),
                branchesSection,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

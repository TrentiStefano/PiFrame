import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/transcript/step_grouping_settings.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/transcript_grouping.dart';
import '../../ui/code/diff_block.dart';
import '../../ui/frame_snack_bar.dart';
import '../tool_timeline/tool_card.dart';
import 'rich_content.dart';
import 'step_group_expansion.dart';

/// Helper to abbreviate file path in the middle (e.g. 'lib/…/file.dart').
String abbreviatePath(String path, {int maxLength = 36}) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.length <= maxLength) return normalized;
  final segments = normalized.split('/');
  if (segments.length <= 2) {
    final start = (maxLength - 3) ~/ 2;
    final end = normalized.length - (maxLength - 3 - start);
    return '${normalized.substring(0, start)}…${normalized.substring(end)}';
  }
  final first = segments.first;
  final last = segments.last;
  final middle = '$first/…/$last';
  if (middle.length <= maxLength) {
    if (segments.length > 3) {
      final candidate2 = '$first/…/${segments[segments.length - 2]}/$last';
      if (candidate2.length <= maxLength) return candidate2;
    }
    return middle;
  }
  if (last.length > maxLength - 4) {
    return '…/${last.substring(last.length - (maxLength - 4))}';
  }
  return middle;
}

/// Helper to abbreviate command (first line, truncated).
String abbreviateCommand(String command, {int maxLength = 45}) {
  final firstLine = command.trim().split('\n').first.trim();
  if (firstLine.length <= maxLength) return firstLine;
  return '${firstLine.substring(0, maxLength - 1)}…';
}

/// Helper extracting an abbreviated target from tool execution state.
String abbreviateTarget(ToolExecutionState tool) {
  final path = tool.args['path'] ?? tool.args['file'] ?? tool.args['filePath'];
  if (path != null && path.toString().trim().isNotEmpty) {
    return abbreviatePath(path.toString().trim());
  }
  final cmd = tool.args['command'] ??
      tool.args['cmd'] ??
      tool.args['CommandLine'] ??
      tool.args['script'];
  if (cmd != null && cmd.toString().trim().isNotEmpty) {
    return abbreviateCommand(cmd.toString().trim());
  }
  final pattern = tool.args['pattern'] ??
      tool.args['query'] ??
      tool.args['search'];
  if (pattern != null && pattern.toString().trim().isNotEmpty) {
    return '"${pattern.toString().trim()}"';
  }
  if (tool.args.isNotEmpty) {
    final firstVal = tool.args.values.first.toString().trim();
    if (firstVal.isNotEmpty) {
      return abbreviateCommand(firstVal, maxLength: 30);
    }
  }
  return '';
}

/// Extracts title for thinking step (first non-empty line or ~80 chars).
String thinkingTitle(String text, {int maxLength = 80}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 'Ragionamento';
  final firstLine = trimmed.split('\n').first.trim();
  if (firstLine.isEmpty) return 'Ragionamento';
  if (firstLine.length <= maxLength) return firstLine;
  return '${firstLine.substring(0, maxLength - 1)}…';
}

/// Formats duration for step group completion.
String formatDuration(Duration d) {
  if (d.inSeconds >= 10) {
    return '${d.inSeconds}s';
  }
  if (d.inMilliseconds >= 1000) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '${d.inMilliseconds}ms';
}

/// Widget displaying a grouped container of intermediate assistant steps.
class StepsGroup extends ConsumerStatefulWidget {
  final StepsGroupBlock block;
  final String sessionId;
  final FrameTokens tokens;
  final VoidCallback? onExpansionChanged;

  const StepsGroup({
    super.key,
    required this.block,
    required this.sessionId,
    required this.tokens,
    this.onExpansionChanged,
  });

  @override
  ConsumerState<StepsGroup> createState() => _StepsGroupState();
}

/// Fraction of the window height that an expanded step list may occupy before
/// it becomes a compact scrollable list.
const double kStepListMaxHeightFraction = 0.5;

class _StepsGroupState extends ConsumerState<StepsGroup> {
  Timer? _liveTimer;
  final ScrollController _stepsScroll = ScrollController();

  /// Whether the compact list content is taller than its maximum height.
  bool _stepsOverflow = false;

  /// Whether the compact list should keep following new steps (running turn
  /// and the user has not scrolled away from the bottom).
  bool _followLatest = true;
  double _lastMaxExtent = 0;

  @override
  void initState() {
    super.initState();
    if (widget.block.isRunning) {
      _startLiveTimer();
    }
  }

  @override
  void didUpdateWidget(covariant StepsGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.block.isRunning && !oldWidget.block.isRunning) {
      _startLiveTimer();
    } else if (!widget.block.isRunning && oldWidget.block.isRunning) {
      _stopLiveTimer();
    }
  }

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.block.isRunning) {
        setState(() {});
      }
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  @override
  void dispose() {
    _stopLiveTimer();
    _stepsScroll.dispose();
    super.dispose();
  }

  bool _onStepsScrollMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    final overflow = metrics.maxScrollExtent > 0.5;
    if (overflow != _stepsOverflow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stepsOverflow != overflow) {
          setState(() => _stepsOverflow = overflow);
        }
      });
    }
    // New steps grew the list: keep showing the latest one while the turn
    // runs, unless the user scrolled up to read earlier steps.
    final grew = metrics.maxScrollExtent > _lastMaxExtent + 0.5;
    _lastMaxExtent = metrics.maxScrollExtent;
    if (grew && widget.block.isRunning && _followLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _stepsScroll.hasClients) {
          _stepsScroll.jumpTo(_stepsScroll.position.maxScrollExtent);
        }
      });
    }
    return false;
  }

  bool _onStepsScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null ||
        notification is UserScrollNotification) {
      final m = notification.metrics;
      _followLatest = m.pixels >= m.maxScrollExtent - 16;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(stepGroupingSettingsProvider);
    final expansionState = ref.watch(
      stepGroupExpansionProvider(widget.sessionId),
    );
    final expansionNotifier = ref.read(
      stepGroupExpansionProvider(widget.sessionId).notifier,
    );

    final expanded = expansionState.isGroupExpanded(
      turnId: widget.block.turnId,
      isRunning: widget.block.isRunning,
      autoCollapse: settings.autoCollapse,
    );

    final fullyExpanded =
        expansionState.isGroupFullyExpanded(widget.block.turnId);
    // Auto-collapse at turn end also returns the list to its compact form.
    if (!expanded && fullyExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          expansionNotifier.setGroupFullyExpanded(widget.block.turnId, false);
        }
      });
    }
    if (!expanded) {
      _stepsOverflow = false;
      _lastMaxExtent = 0;
      _followLatest = true;
    }

    final latestStepLabel = _formatLatestStep(widget.block.latestStep);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(
          color: widget.block.failed
              ? tokens.danger.withValues(alpha: 0.6)
              : tokens.borderStrong,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          _buildHeader(
            context: context,
            expanded: expanded,
            strings: strings,
            tokens: tokens,
            latestStepLabel: latestStepLabel,
            onTap: () {
              expansionNotifier.toggleGroup(
                widget.block.turnId,
                expanded,
                runningTurnId:
                    widget.block.isRunning ? widget.block.turnId : null,
              );
              widget.onExpansionChanged?.call();
            },
          ),

          // Body: steps indented with a 1px left line connecting them
          if (expanded && widget.block.steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: 14,
                right: 10,
                bottom: 8,
                top: 2,
              ),
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: tokens.borderStrong,
                      width: 1.0,
                    ),
                  ),
                ),
                child: _buildStepList(
                  context: context,
                  fullyExpanded: fullyExpanded,
                  tokens: tokens,
                  strings: strings,
                  expansionState: expansionState,
                  expansionNotifier: expansionNotifier,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepList({
    required BuildContext context,
    required bool fullyExpanded,
    required FrameTokens tokens,
    required AppStrings strings,
    required StepGroupExpansionState expansionState,
    required StepGroupExpansionNotifier expansionNotifier,
  }) {
    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < widget.block.steps.length; i++)
          _buildStepItem(
            context: context,
            step: widget.block.steps[i],
            tokens: tokens,
            strings: strings,
            expansionState: expansionState,
            expansionNotifier: expansionNotifier,
          ),
      ],
    );
    if (fullyExpanded) return steps;

    final maxHeight =
        MediaQuery.sizeOf(context).height * kStepListMaxHeightFraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          key: ValueKey('step_group_compact_list_${widget.block.groupId}'),
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onStepsScrollMetrics,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onStepsScroll,
              child: Scrollbar(
                controller: _stepsScroll,
                thumbVisibility: _stepsOverflow,
                child: SingleChildScrollView(
                  controller: _stepsScroll,
                  primary: false,
                  padding: EdgeInsets.only(right: _stepsOverflow ? 10 : 0),
                  child: steps,
                ),
              ),
            ),
          ),
        ),
        if (_stepsOverflow)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                key: ValueKey(
                  'step_group_expand_all_${widget.block.groupId}',
                ),
                onPressed: () {
                  expansionNotifier.setGroupFullyExpanded(
                    widget.block.turnId,
                    true,
                  );
                  widget.onExpansionChanged?.call();
                },
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 28),
                  visualDensity: VisualDensity.compact,
                  textStyle: TextStyle(
                    fontFamily: tokens.uiFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.keyboard_double_arrow_down, size: 16),
                label: Text(
                  strings.stepGroupShowAllSteps(widget.block.steps.length),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatLatestStep(StepItem? step) {
    if (step == null) return '';
    if (step is ToolStep) {
      final target = abbreviateTarget(step.tool);
      return target.isNotEmpty ? '${step.toolName} $target' : step.toolName;
    }
    if (step is ThinkingStep) {
      return thinkingTitle(step.text);
    }
    if (step is IntermediateTextStep) {
      return thinkingTitle(step.text);
    }
    return '';
  }

  Widget _buildHeader({
    required BuildContext context,
    required bool expanded,
    required AppStrings strings,
    required FrameTokens tokens,
    required String latestStepLabel,
    required VoidCallback onTap,
  }) {
    final isRunning = widget.block.isRunning;
    final hasError = widget.block.hasError;
    final aborted = widget.block.aborted;
    final failed = widget.block.failed;
    final stepCount = widget.block.stepCount;

    String headerLabel;
    Widget statusIcon;

    if (isRunning) {
      statusIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: tokens.agentWorking,
        ),
      );
      headerLabel = latestStepLabel.isNotEmpty
          ? '${strings.stepGroupWorking} · $latestStepLabel'
          : strings.stepGroupWorking;
    } else if (aborted) {
      statusIcon = Icon(
        Icons.stop_circle_outlined,
        size: 15,
        color: tokens.textMuted,
      );
      headerLabel = strings.stepGroupStopped(stepCount);
    } else if (failed) {
      statusIcon = Icon(
        Icons.error_outline,
        size: 15,
        color: tokens.danger,
      );
      headerLabel = strings.stepGroupStoppedWithErrors(stepCount);
    } else {
      // The turn completed. Failed tool calls along the way are flagged with
      // a status icon; they do not turn the summary into a failure.
      statusIcon = hasError
          ? Tooltip(
              message: strings.stepGroupSomeStepsFailed,
              child: Icon(
                Icons.error_outline,
                key: const ValueKey('step_group_steps_failed_icon'),
                size: 15,
                color: tokens.warning,
              ),
            )
          : Icon(
              Icons.check_circle_outline,
              size: 15,
              color: tokens.agentSettled,
            );
      if (widget.block.elapsed != null) {
        headerLabel = strings.stepGroupCompletedIn(
          stepCount,
          formatDuration(widget.block.elapsed!),
        );
      } else if (stepCount > 0) {
        headerLabel = strings.stepGroupCompleted(stepCount);
      } else {
        headerLabel = strings.stepGroupFinished(stepCount);
      }
    }

    return Semantics(
      button: true,
      expanded: expanded,
      label: headerLabel,
      child: InkWell(
        key: ValueKey('step_group_header_${widget.block.groupId}'),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              statusIcon,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isRunning
                        ? tokens.agentWorking
                        : failed
                            ? tokens.danger
                            : tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: tokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem({
    required BuildContext context,
    required StepItem step,
    required FrameTokens tokens,
    required AppStrings strings,
    required StepGroupExpansionState expansionState,
    required StepGroupExpansionNotifier expansionNotifier,
  }) {
    if (step is ThinkingStep) {
      return _buildThinkingStep(
        context: context,
        step: step,
        tokens: tokens,
        strings: strings,
        isExpanded: expansionState.isStepExpanded(step.id),
        onToggle: () {
          expansionNotifier.toggleStep(step.id);
          widget.onExpansionChanged?.call();
        },
      );
    }
    if (step is ToolStep) {
      return _buildToolStep(
        context: context,
        step: step,
        tokens: tokens,
        strings: strings,
        isExpanded: expansionState.isStepExpanded(step.id),
        onToggle: () {
          expansionNotifier.toggleStep(step.id);
          widget.onExpansionChanged?.call();
        },
      );
    }
    if (step is IntermediateTextStep) {
      return _buildIntermediateTextStep(
        step: step,
        tokens: tokens,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildThinkingStep({
    required BuildContext context,
    required ThinkingStep step,
    required FrameTokens tokens,
    required AppStrings strings,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final effectiveExpanded = isExpanded || step.isStreaming;
    final trimmed = step.text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final title = thinkingTitle(trimmed);
    final preview = trimmed.split('\n').skip(1).join('\n').trim();

    return Padding(
      key: ValueKey('thinking_step_${step.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: effectiveExpanded,
            label: 'Ragionamento · $title',
            child: InkWell(
              key: ValueKey('thinking_step_header_${step.id}'),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 14,
                      color: tokens.thinking,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Ragionamento',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        effectiveExpanded ? '' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (step.isStreaming) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.agentWorking,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      effectiveExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 15,
                      color: tokens.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!effectiveExpanded && preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 8, top: 1),
              child: Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
          if (effectiveExpanded)
            Container(
              margin: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: tokens.borderStrong,
                    width: 2,
                  ),
                ),
              ),
              child: SelectableText(
                step.text,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolStep({
    required BuildContext context,
    required ToolStep step,
    required FrameTokens tokens,
    required AppStrings strings,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final tool = step.tool;
    final isRunning = tool.isRunning;
    final isError = tool.isError;
    final toolColor = getToolColor(tool.toolName, tokens);
    final target = abbreviateTarget(tool);

    // Timing calculation
    final durationMs = tool.elapsedMsAt(DateTime.now().millisecondsSinceEpoch);
    String? durationText;
    if (isRunning && durationMs != null) {
      final s = (durationMs / 1000).floor();
      durationText = '${s}s';
    } else if (tool.durationMs != null) {
      if (tool.durationMs! >= 5000) {
        durationText = '${(tool.durationMs! / 1000).round()}s';
      } else {
        durationText = '${tool.durationMs}ms';
      }
    }

    return Padding(
      key: ValueKey('tool_step_${step.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact single row
          Semantics(
            button: true,
            expanded: isExpanded,
            label: '${step.toolName} $target',
            child: InkWell(
              key: ValueKey('tool_step_header_${step.id}'),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                child: Row(
                  children: [
                    Icon(
                      getToolIcon(step.toolName),
                      size: 14,
                      color: isError
                          ? tokens.agentError
                          : isRunning
                              ? tokens.agentWorking
                              : toolColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Row(
                        children: [
                          Text(
                            step.toolName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11.5,
                              fontFamily: tokens.uiFontFamily,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (target.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                target,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tokens.syntaxString,
                                  fontSize: 11,
                                  fontFamily: tokens.monoFontFamily,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (durationText != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                            tokens.radiusSm,
                          ),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isRunning) ...[
                              Icon(
                                Icons.timer_outlined,
                                size: 10,
                                color: tokens.agentWorking,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              durationText,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 9.5,
                                fontFamily: tokens.monoFontFamily,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (isRunning)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: tokens.agentWorking,
                        ),
                      )
                    else if (isError)
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: tokens.agentError,
                      )
                    else
                      Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: tokens.agentSettled,
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded detail: Input & Output with Show all / Show less toggle
          if (isExpanded)
            _ToolStepExpandedView(
              key: ValueKey('tool_step_expanded_${step.id}'),
              step: step,
              tokens: tokens,
              strings: strings,
            ),
        ],
      ),
    );
  }

  Widget _buildIntermediateTextStep({
    required IntermediateTextStep step,
    required FrameTokens tokens,
  }) {
    final cwd = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.cwd),
    );
    return Padding(
      key: ValueKey('intermediate_text_step_${step.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Opacity(
          opacity: 0.9,
          child: RichContent(text: step.text, cwd: cwd),
        ),
      ),
    );
  }
}

/// Detail view inside an expanded ToolStep, showing input (pretty JSON)
/// and output (or diff for edits) with 'Show all'/'Show less' truncation toggles.
class _ToolStepExpandedView extends StatefulWidget {
  final ToolStep step;
  final FrameTokens tokens;
  final AppStrings strings;

  const _ToolStepExpandedView({
    super.key,
    required this.step,
    required this.tokens,
    required this.strings,
  });

  @override
  State<_ToolStepExpandedView> createState() => _ToolStepExpandedViewState();
}

class _ToolStepExpandedViewState extends State<_ToolStepExpandedView> {
  bool _showAllInput = false;
  bool _showAllOutput = false;

  static bool _isLongText(String text) {
    final lines = text.split('\n');
    return lines.length > 20 || text.length > 4000;
  }

  static String _truncateText(String text) {
    final lines = text.split('\n');
    if (lines.length > 20) {
      return '${lines.sublist(0, 20).join('\n')}\n…';
    }
    if (text.length > 4000) {
      return '${text.substring(0, 4000)}…';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final strings = widget.strings;
    final tool = widget.step.tool;
    final parsed = parseToolOutput(tool);

    String prettyInput = '';
    if (tool.args.isNotEmpty) {
      try {
        prettyInput = const JsonEncoder.withIndent('  ').convert(tool.args);
      } catch (_) {
        prettyInput = tool.args.toString();
      }
    }

    final hasInput = prettyInput.trim().isNotEmpty;
    final hasOutput = tool.output.trim().isNotEmpty;
    final isInputLong = _isLongText(prettyInput);
    final isOutputLong = _isLongText(tool.output);

    return Container(
      margin: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Edit diff if available
          if (parsed.diffText != null) ...[
            if (parsed.summaryText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  parsed.summaryText!,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            DiffBlock(
              diffText: parsed.diffText!,
              filename: parsed.filename,
            ),
            if (hasInput || (hasOutput && parsed.diffText != tool.output))
              const SizedBox(height: 8),
          ],

          // Input Section
          if (hasInput) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  strings.stepGroupInput,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: prettyInput));
                    FrameSnackBar.show(
                      context,
                      message: 'Input copiato',
                      duration: const Duration(seconds: 1),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_outlined,
                          size: 11,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Copia',
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
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: SelectableText(
                _showAllInput || !isInputLong
                    ? prettyInput
                    : _truncateText(prettyInput),
                style: TextStyle(
                  color: tokens.syntaxNumber,
                  fontSize: 11,
                  fontFamily: tokens.monoFontFamily,
                  height: 1.4,
                ),
              ),
            ),
            if (isInputLong) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('tool_step_toggle_input_truncation'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () {
                    setState(() => _showAllInput = !_showAllInput);
                  },
                  child: Text(
                    _showAllInput
                        ? strings.stepGroupShowLess
                        : strings.stepGroupShowAll,
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (hasOutput && parsed.diffText == null)
              const SizedBox(height: 8),
          ],

          // Output Section (only if not already shown as diff)
          if (hasOutput && parsed.diffText == null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  strings.stepGroupOutput,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: tool.output));
                    FrameSnackBar.show(
                      context,
                      message: 'Output copiato',
                      duration: const Duration(seconds: 1),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_outlined,
                          size: 11,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Copia',
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
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: SelectableText(
                _showAllOutput || !isOutputLong
                    ? tool.output
                    : _truncateText(tool.output),
                style: TextStyle(
                  color: tool.isError
                      ? tokens.agentError
                      : tokens.textSecondary,
                  fontSize: 11,
                  fontFamily: tokens.monoFontFamily,
                  height: 1.4,
                ),
              ),
            ),
            if (isOutputLong) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('tool_step_toggle_output_truncation'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () {
                    setState(() => _showAllOutput = !_showAllOutput);
                  },
                  child: Text(
                    _showAllOutput
                        ? strings.stepGroupShowLess
                        : strings.stepGroupShowAll,
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

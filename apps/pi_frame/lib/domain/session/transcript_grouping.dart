import 'session_state.dart';

/// Strategy for grouping intermediate assistant steps in a turn.
enum StepGroupingMode {
  /// Today's behavior: every entry is rendered as an individual block.
  off,

  /// Group a turn only when it contains model thinking (committed or streaming).
  withThinking,

  /// Group a turn whenever it has at least one intermediate step (thinking, tool call, intermediate text).
  always,

  /// Super-compact mode: compacts all intermediate steps and non-final answers into a single group,
  /// showing only the user message, an expandable step indicator with elapsed time, and the final answer.
  full,
}

/// Bundles the live/in-progress state for the active turn in a transcript.
class TranscriptLiveState {
  final bool isRunning;
  final String streamingThinking;
  final String streamingText;
  final List<ToolExecutionState> activeToolCalls;
  final bool hasError;
  final bool aborted;

  const TranscriptLiveState({
    this.isRunning = false,
    this.streamingThinking = '',
    this.streamingText = '',
    this.activeToolCalls = const [],
    this.hasError = false,
    this.aborted = false,
  });

  static const empty = TranscriptLiveState();

  bool get hasContent =>
      streamingThinking.trim().isNotEmpty || streamingText.trim().isNotEmpty || activeToolCalls.isNotEmpty;

  TranscriptLiveState copyWith({
    bool? isRunning,
    String? streamingThinking,
    String? streamingText,
    List<ToolExecutionState>? activeToolCalls,
    bool? hasError,
    bool? aborted,
  }) {
    return TranscriptLiveState(
      isRunning: isRunning ?? this.isRunning,
      streamingThinking: streamingThinking ?? this.streamingThinking,
      streamingText: streamingText ?? this.streamingText,
      activeToolCalls: activeToolCalls ?? this.activeToolCalls,
      hasError: hasError ?? this.hasError,
      aborted: aborted ?? this.aborted,
    );
  }

  /// Derives live state directly from a [SessionState].
  factory TranscriptLiveState.fromSession(SessionState session) {
    final lastEntry = session.entries.isNotEmpty ? session.entries.last : null;
    final lastStopReason = lastEntry?.metadata?['stopReason']?.toString().toLowerCase();
    final lastCancelled = lastEntry?.metadata?['cancelled'] == true;

    final lastUserEntry = session.entries.reversed.where((e) => e.role == 'user').firstOrNull;
    final hasUserSendError = lastUserEntry?.metadata?['sendError'] != null;

    final hasActiveError =
        session.agentStatus.name.toLowerCase().contains('error') ||
        session.activeToolCalls.values.any((t) => t.isError) ||
        lastStopReason == 'error' ||
        hasUserSendError;

    final isAborted = lastStopReason == 'aborted' || lastCancelled;

    final isRunning =
        session.agentStatus.name == 'working' ||
        session.agentStatus.name == 'retrying' ||
        session.agentStatus.name == 'compacting' ||
        session.isStreaming;

    return TranscriptLiveState(
      isRunning: isRunning,
      streamingThinking: session.currentStreamingThinking,
      streamingText: session.currentStreamingText,
      activeToolCalls: session.activeToolCalls.values.toList(),
      hasError: hasActiveError,
      aborted: isAborted,
    );
  }
}

/// Sealed base class for elements produced by [groupTranscript].
sealed class TranscriptBlock {
  const TranscriptBlock();
}

/// A block rendered directly as a single transcript item.
/// Used for user messages, milestones (compaction/branch summaries, bashExecution, custom),
/// and un-grouped assistant entries.
final class EntryBlock extends TranscriptBlock {
  final SessionEntry entry;

  const EntryBlock(this.entry);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EntryBlock && runtimeType == other.runtimeType && entry == other.entry;

  @override
  int get hashCode => entry.hashCode;

  @override
  String toString() => 'EntryBlock(${entry.id}, role: ${entry.role})';
}

/// A grouped container of intermediate steps for a turn.
final class StepsGroupBlock extends TranscriptBlock {
  /// Stable group identifier: `steps_<turnId>`.
  final String groupId;

  /// Identifier of the turn (user entry id, or 'turn_start').
  final String turnId;

  /// Ordered chronological list of intermediate steps.
  final List<StepItem> steps;

  /// Whether the turn is currently executing.
  final bool isRunning;

  /// Whether any step or turn termination encountered an error. A completed
  /// turn can have this set because a single tool call failed.
  final bool hasError;

  /// Whether the turn was aborted / cancelled.
  final bool aborted;

  /// Whether the turn itself ended in failure (model/stream error, send
  /// error, worker error) instead of reaching a normal end.
  final bool failed;

  /// Total count of thinking steps and tool execution steps (excludes intermediate text).
  final int stepCount;

  /// Duration from turn start (user entry) to the last step / final entry timestamp.
  final Duration? elapsed;

  /// Most recent step in the group (useful for "Working…" header labels).
  final StepItem? latestStep;

  const StepsGroupBlock({
    required this.groupId,
    required this.turnId,
    required this.steps,
    required this.isRunning,
    required this.hasError,
    required this.aborted,
    this.failed = false,
    required this.stepCount,
    this.elapsed,
    this.latestStep,
  });

  @override
  String toString() => 'StepsGroupBlock($groupId, stepCount: $stepCount, isRunning: $isRunning, hasError: $hasError)';
}

/// An intermediate assistant response rendered outside the compacted step groups,
/// between groups of intermediate tool and thinking steps.
final class IntermediateTextBlock extends TranscriptBlock {
  /// Assistant entry stripped of thinking and tool calls.
  final SessionEntry entry;

  /// Identifier of the turn.
  final String turnId;

  const IntermediateTextBlock({required this.entry, required this.turnId});

  String get text => entry.text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntermediateTextBlock &&
          runtimeType == other.runtimeType &&
          entry == other.entry &&
          turnId == other.turnId;

  @override
  int get hashCode => Object.hash(entry, turnId);

  @override
  String toString() => 'IntermediateTextBlock(entry: ${entry.id}, turnId: $turnId)';
}

/// The final assistant response of a turn, rendered as text only.
/// Any thinking or tool calls associated with the original entry belong to the [StepsGroupBlock].
final class FinalTextBlock extends TranscriptBlock {
  /// Assistant entry stripped of thinking and tool calls so UI can render text bubble directly.
  final SessionEntry entry;

  /// Identifier of the turn.
  final String turnId;

  const FinalTextBlock({required this.entry, required this.turnId});

  String get text => entry.text;

  @override
  String toString() => 'FinalTextBlock(entry: ${entry.id}, turnId: $turnId)';
}

/// Live streaming candidate final text or live stream marker during active running turns.
final class LiveTailBlock extends TranscriptBlock {
  final String turnId;
  final String text;
  final TranscriptLiveState live;

  const LiveTailBlock({required this.turnId, required this.text, required this.live});

  bool get isRunning => live.isRunning;
  bool get hasText => text.trim().isNotEmpty;

  @override
  String toString() => 'LiveTailBlock(turnId: $turnId, text: "$text", isRunning: $isRunning)';
}

/// Sealed base class for items inside a [StepsGroupBlock].
///
/// Step ID Stability:
/// - ToolStep: uses `ToolExecutionState.toolCallId` which is generated daemon-side at start
///   and retained when committed into `SessionEntry.toolCalls`. This guarantees tool step IDs
///   remain identical during streaming execution and after commit.
/// - ThinkingStep: streaming thinking uses `'live_${turnId}_thinking'`; once committed to an
///   entry, it transitions to `'${entry.id}_thinking'` because entry IDs are assigned on commit.
/// - IntermediateTextStep: streaming intermediate text uses `'live_${turnId}_text'`; once
///   committed, it uses `'${entry.id}_text'`.
sealed class StepItem {
  const StepItem();

  String get id;
  int? get timestamp;
}

/// A model thinking step.
final class ThinkingStep extends StepItem {
  @override
  final String id;
  final String text;
  final bool isStreaming;
  @override
  final int? timestamp;

  const ThinkingStep({required this.id, required this.text, this.isStreaming = false, this.timestamp});

  @override
  String toString() => 'ThinkingStep($id, streaming: $isStreaming)';
}

/// A tool execution step, reusing [ToolExecutionState] directly.
final class ToolStep extends StepItem {
  @override
  final String id;
  final ToolExecutionState tool;
  @override
  final int? timestamp;

  const ToolStep({required this.id, required this.tool, this.timestamp});

  String get toolName => tool.toolName;
  String get toolCallId => tool.toolCallId;
  Map<String, dynamic> get args => tool.args;
  String get output => tool.output;
  bool get isError => tool.isError;
  bool get isRunning => tool.isRunning;
  int? get startedAt => tool.startedAt;
  int? get durationMs => tool.durationMs;
  Duration? get duration => durationMs != null ? Duration(milliseconds: durationMs!) : null;

  @override
  String toString() => 'ToolStep($id, name: $toolName, isRunning: $isRunning, isError: $isError)';
}

/// An intermediate assistant text block that occurred prior to later tool calls or assistant messages.
final class IntermediateTextStep extends StepItem {
  @override
  final String id;
  final String text;
  final SessionEntry? entry;
  @override
  final int? timestamp;

  const IntermediateTextStep({required this.id, required this.text, this.entry, this.timestamp});

  @override
  String toString() => 'IntermediateTextStep($id, text: "$text")';
}

/// A completed subagent notification step inside a [StepsGroupBlock].
final class SubagentNotificationStep extends StepItem {
  @override
  final String id;
  final SessionEntry entry;
  @override
  final int? timestamp;

  const SubagentNotificationStep({required this.id, required this.entry, this.timestamp});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubagentNotificationStep && runtimeType == other.runtimeType && id == other.id && entry == other.entry;

  @override
  int get hashCode => Object.hash(id, entry);

  @override
  String toString() => 'SubagentNotificationStep($id)';
}

/// Internal helper model holding entries for a single turn.
class _TurnData {
  final String turnId;
  final SessionEntry? userEntry;
  final List<SessionEntry> nonUserEntries;
  final bool isLastTurn;

  const _TurnData({
    required this.turnId,
    required this.userEntry,
    required this.nonUserEntries,
    required this.isLastTurn,
  });
}

bool _isSubagentNotificationEntry(SessionEntry entry) {
  if (entry.role == 'custom') {
    final customType = entry.metadata?['customType']?.toString();
    if (customType == 'subagent-notification') return true;
    if (entry.text.contains('<task-notification>')) return true;
  }
  return false;
}

/// Pure function grouping transcript entries according to [mode] and [live] state.
///
/// Guarantees NO LOSS: every entry's text, thinking, and tool calls appear in exactly
/// one block/step.
List<TranscriptBlock> groupTranscript({
  required List<SessionEntry> entries,
  required StepGroupingMode mode,
  required TranscriptLiveState live,
  bool showIntermediateAnswers = true,
}) {
  // Pre-filter internal/junk messages exactly like transcript_view
  final cleanEntries = entries.where((e) => !e.isJunkOrInternal).toList();

  // Mode off: return every entry as an EntryBlock, plus LiveTailBlock if live content exists.
  if (mode == StepGroupingMode.off) {
    final result = <TranscriptBlock>[for (final entry in cleanEntries) EntryBlock(entry)];
    if (live.isRunning && (live.hasContent || live.streamingText.isNotEmpty)) {
      final lastUser = cleanEntries.reversed.where((e) => e.role == 'user').firstOrNull;
      final turnId = (lastUser?.metadata?['optimisticId'] as String?) ?? lastUser?.id ?? 'turn_start';
      result.add(LiveTailBlock(turnId: turnId, text: live.streamingText, live: live));
    }
    return result;
  }

  // Partition entries into turns (from user entry to next user entry).
  final turns = _partitionTurns(cleanEntries);
  final output = <TranscriptBlock>[];

  for (final turn in turns) {
    _processTurn(turn: turn, mode: mode, live: live, output: output, showIntermediateAnswers: showIntermediateAnswers);
  }

  return output;
}

List<_TurnData> _partitionTurns(List<SessionEntry> entries) {
  if (entries.isEmpty) {
    return const [_TurnData(turnId: 'turn_start', userEntry: null, nonUserEntries: [], isLastTurn: true)];
  }

  final turns = <_TurnData>[];
  final userIndices = <int>[];
  for (int i = 0; i < entries.length; i++) {
    if (entries[i].role == 'user') {
      userIndices.add(i);
    }
  }

  if (userIndices.isEmpty) {
    turns.add(_TurnData(turnId: 'turn_start', userEntry: null, nonUserEntries: entries, isLastTurn: true));
    return turns;
  }

  // Pre-user entries if any
  if (userIndices.first > 0) {
    turns.add(
      _TurnData(
        turnId: 'turn_start',
        userEntry: null,
        nonUserEntries: entries.sublist(0, userIndices.first),
        isLastTurn: false,
      ),
    );
  }

  for (int u = 0; u < userIndices.length; u++) {
    final userIdx = userIndices[u];
    final nextUserIdx = u + 1 < userIndices.length ? userIndices[u + 1] : entries.length;
    final isLast = u == userIndices.length - 1;
    final userEntry = entries[userIdx];
    final nonUserEntries = entries.sublist(userIdx + 1, nextUserIdx);

    final turnId = (userEntry.metadata?['optimisticId'] as String?) ?? userEntry.id;
    turns.add(_TurnData(turnId: turnId, userEntry: userEntry, nonUserEntries: nonUserEntries, isLastTurn: isLast));
  }

  return turns;
}

void _processTurn({
  required _TurnData turn,
  required StepGroupingMode mode,
  required TranscriptLiveState live,
  required List<TranscriptBlock> output,
  bool showIntermediateAnswers = true,
}) {
  final assistantEntries = turn.nonUserEntries.where((e) => e.role == 'assistant').toList();

  final hasCommittedThinking = assistantEntries.any((e) => e.thinking != null && e.thinking!.trim().isNotEmpty);
  final hasStreamingThinking = turn.isLastTurn && live.isRunning && live.streamingThinking.trim().isNotEmpty;

  final hasCommittedTools = assistantEntries.any((e) => e.toolCalls.isNotEmpty);
  final hasActiveTools = turn.isLastTurn && live.isRunning && live.activeToolCalls.isNotEmpty;
  final hasTools = hasCommittedTools || hasActiveTools;

  // Identify final assistant entry candidate (if any).
  // While the turn is actively running, no committed entry is final yet.
  // Only once the turn completes (or stops running) is the last assistant entry final.
  SessionEntry? finalAssistantEntry;
  if (!hasActiveTools && !(turn.isLastTurn && live.isRunning)) {
    for (int i = assistantEntries.length - 1; i >= 0; i--) {
      final asst = assistantEntries[i];
      if (asst.toolCallsAfterText.isNotEmpty) {
        break;
      }
      if (asst.text.trim().isNotEmpty) {
        final asstIdx = turn.nonUserEntries.indexOf(asst);
        final after = turn.nonUserEntries.sublist(asstIdx + 1);
        final everythingAfterHasNoTextAndNoTools = after.every((e) => e.text.trim().isEmpty && e.toolCalls.isEmpty);
        if (everythingAfterHasNoTextAndNoTools) {
          finalAssistantEntry = asst;
        }
        break;
      }
    }
  }

  // An intermediate text step exists if an assistant message with text is not the final assistant entry,
  // or if an assistant message has tool calls after its text.
  bool hasCommittedIntermediateText = assistantEntries
      .where((e) => e.id != finalAssistantEntry?.id)
      .any((e) => e.text.trim().isNotEmpty);
  if (!hasCommittedIntermediateText && assistantEntries.isNotEmpty) {
    final last = assistantEntries.last;
    if (last.text.trim().isNotEmpty && (last.toolCallsAfterText.isNotEmpty || hasActiveTools)) {
      hasCommittedIntermediateText = true;
    }
  }

  // Thinking encompasses explicit model thinking as well as intermediate reasoning answers.
  final hasThinking = hasCommittedThinking || hasStreamingThinking || hasCommittedIntermediateText;

  final hasSubagents = turn.nonUserEntries.any(_isSubagentNotificationEntry);

  final hasIntermediateSteps =
      hasThinking ||
      hasTools ||
      hasCommittedIntermediateText ||
      hasSubagents ||
      (mode == StepGroupingMode.full && turn.isLastTurn && live.isRunning);

  final bool shouldGroup;
  switch (mode) {
    case StepGroupingMode.off:
      shouldGroup = false;
      break;
    case StepGroupingMode.withThinking:
      shouldGroup = hasThinking;
      break;
    case StepGroupingMode.always:
    case StepGroupingMode.full:
      shouldGroup = hasIntermediateSteps;
      break;
  }

  // If not grouped, render turn in classic entry order
  if (!shouldGroup) {
    if (turn.userEntry != null) {
      output.add(EntryBlock(turn.userEntry!));
    }
    for (final entry in turn.nonUserEntries) {
      // A turn answered straight away, with no steps at all, still ends in
      // the agent's final answer: show it as one, in the same card and text
      // colour as an answer after steps. Turns left ungrouped by the mode
      // (tools without thinking under "with thinking") keep the classic
      // layout, and an entry with tool calls or thinking is never stripped.
      final isPlainFinalAnswer =
          !hasIntermediateSteps &&
          entry.id == finalAssistantEntry?.id &&
          entry.toolCalls.isEmpty &&
          (entry.thinking == null || entry.thinking!.trim().isEmpty);
      output.add(isPlainFinalAnswer ? FinalTextBlock(entry: entry, turnId: turn.turnId) : EntryBlock(entry));
    }
    if (turn.isLastTurn && live.isRunning && (live.hasContent || live.streamingText.isNotEmpty)) {
      output.add(LiveTailBlock(turnId: turn.turnId, text: live.streamingText, live: live));
    }
    return;
  }

  // GROUPED TURN
  // 1. User entry (if any) is emitted first
  if (turn.userEntry != null) {
    output.add(EntryBlock(turn.userEntry!));
  }

  // Error and abort detection
  final hasEntryError = turn.nonUserEntries.any(
    (e) =>
        e.metadata?['sendError'] != null ||
        e.metadata?['stopReason'] == 'error' ||
        (e.role == 'bashExecution' && e.metadata?['exitCode'] is int && e.metadata!['exitCode'] != 0),
  );
  final hasUserSendError = turn.userEntry?.metadata?['sendError'] != null;
  final lastAssistant = assistantEntries.lastOrNull;
  final hasTurnEndError =
      lastAssistant?.metadata?['stopReason'] == 'error' ||
      turn.nonUserEntries.any((e) => e.metadata?['sendError'] != null);
  final hasEntryAbort = turn.nonUserEntries.any(
    (e) => e.metadata?['stopReason'] == 'aborted' || e.metadata?['cancelled'] == true,
  );
  final isAborted = hasEntryAbort || (turn.isLastTurn && live.aborted);
  final isTurnRunning = turn.isLastTurn && live.isRunning;
  final isFailed = !isAborted && (hasTurnEndError || hasUserSendError || (turn.isLastTurn && live.hasError));
  final hasGeneralError = hasEntryError || hasUserSendError || isAborted || (turn.isLastTurn && live.hasError);

  if (mode != StepGroupingMode.full && showIntermediateAnswers && hasCommittedIntermediateText) {
    // Multi-group flow: intermediate answers are emitted OUTSIDE the step groups,
    // separated by compacted intermediate steps.
    final currentSteps = <StepItem>[];
    int groupIndex = 0;

    void emitGroup({int? endTimestampMs, bool isTrailing = false}) {
      if (currentSteps.isEmpty) return;

      final groupId = groupIndex == 0 ? 'steps_${turn.turnId}' : 'steps_${turn.turnId}_$groupIndex';
      final stepCount = currentSteps
          .where((s) => s is ThinkingStep || s is ToolStep || s is SubagentNotificationStep)
          .length;
      final latestStep = currentSteps.last;

      Duration? elapsed;
      final userTimestamp = turn.userEntry?.timestamp;
      if (userTimestamp != null && userTimestamp > 0) {
        int? endTimestamp = endTimestampMs;
        if (endTimestamp == null) {
          for (final s in currentSteps.reversed) {
            if (s is ToolStep && s.startedAt != null && s.startedAt! > 0) {
              final startedMs = normalizeTimestampToMs(s.startedAt!);
              endTimestamp = startedMs + (s.durationMs ?? 0);
              break;
            } else if (s.timestamp != null && s.timestamp! > 0) {
              endTimestamp = normalizeTimestampToMs(s.timestamp!);
              break;
            }
          }
        }
        if (endTimestamp != null) {
          final startMs = normalizeTimestampToMs(userTimestamp);
          if (endTimestamp >= startMs) {
            elapsed = Duration(milliseconds: endTimestamp - startMs);
          }
        }
      }

      final hasToolError = currentSteps.whereType<ToolStep>().any((s) => s.isError);
      final hasSubagentError = currentSteps.whereType<SubagentNotificationStep>().any(
        (s) =>
            s.entry.metadata?['failed'] == true ||
            s.entry.metadata?['isError'] == true ||
            s.entry.metadata?['status'] == 'failed' ||
            s.entry.metadata?['status'] == 'error' ||
            s.entry.metadata?['sendError'] != null,
      );
      final isRunningNow = isTurnRunning && isTrailing;
      final groupHasError = hasToolError || hasSubagentError;

      output.add(
        StepsGroupBlock(
          groupId: groupId,
          turnId: turn.turnId,
          steps: List<StepItem>.unmodifiable(currentSteps),
          isRunning: isRunningNow,
          hasError: groupHasError,
          aborted: isAborted,
          failed: isTrailing && isFailed,
          stepCount: stepCount,
          elapsed: elapsed,
          latestStep: latestStep,
        ),
      );
      groupIndex++;
      currentSteps.clear();
    }

    for (final entry in turn.nonUserEntries) {
      if (_isSubagentNotificationEntry(entry)) {
        currentSteps.add(
          SubagentNotificationStep(id: '${entry.id}_subagent', entry: entry, timestamp: entry.timestamp),
        );
        continue;
      }

      if (entry.role != 'assistant') {
        emitGroup();
        output.add(EntryBlock(entry));
        continue;
      }

      // Assistant entry
      if (entry.thinking != null && entry.thinking!.trim().isNotEmpty) {
        currentSteps.add(
          ThinkingStep(
            id: '${entry.id}_thinking',
            text: entry.thinking!.trim(),
            isStreaming: false,
            timestamp: entry.timestamp,
          ),
        );
      }

      final toolsBeforeText = entry.toolCallsBeforeText;
      for (int t = 0; t < toolsBeforeText; t++) {
        final tool = entry.toolCalls[t];
        currentSteps.add(
          ToolStep(
            id: tool.toolCallId.isNotEmpty ? tool.toolCallId : '${entry.id}_tool_$t',
            tool: tool,
            timestamp: tool.startedAt ?? entry.timestamp,
          ),
        );
      }

      if (entry.id == finalAssistantEntry?.id) {
        final endMs = entry.timestamp > 0 ? normalizeTimestampToMs(entry.timestamp) : null;
        emitGroup(endTimestampMs: endMs);
        output.add(
          FinalTextBlock(
            entry: SessionEntry(
              id: entry.id,
              role: entry.role,
              text: entry.text,
              thinking: null,
              toolCalls: const [],
              timestamp: entry.timestamp,
              metadata: entry.metadata,
            ),
            turnId: turn.turnId,
          ),
        );
      } else if (entry.text.trim().isNotEmpty) {
        final endMs = entry.timestamp > 0 ? normalizeTimestampToMs(entry.timestamp) : null;
        emitGroup(endTimestampMs: endMs);
        output.add(
          IntermediateTextBlock(
            entry: SessionEntry(
              id: entry.id,
              role: entry.role,
              text: entry.text,
              thinking: null,
              toolCalls: const [],
              timestamp: entry.timestamp,
              metadata: entry.metadata,
            ),
            turnId: turn.turnId,
          ),
        );
      }

      for (int t = toolsBeforeText; t < entry.toolCalls.length; t++) {
        final tool = entry.toolCalls[t];
        currentSteps.add(
          ToolStep(
            id: tool.toolCallId.isNotEmpty ? tool.toolCallId : '${entry.id}_tool_$t',
            tool: tool,
            timestamp: tool.startedAt ?? entry.timestamp,
          ),
        );
      }
    }

    if (turn.isLastTurn && live.isRunning) {
      if (live.streamingThinking.trim().isNotEmpty) {
        currentSteps.add(
          ThinkingStep(id: 'live_${turn.turnId}_thinking', text: live.streamingThinking.trim(), isStreaming: true),
        );
      }

      if (hasActiveTools) {
        final existingToolIds = {for (final s in currentSteps.whereType<ToolStep>()) s.toolCallId};
        for (int t = 0; t < live.activeToolCalls.length; t++) {
          final tool = live.activeToolCalls[t];
          if (tool.toolCallId.isNotEmpty && existingToolIds.contains(tool.toolCallId)) {
            continue;
          }
          final stepId = tool.toolCallId.isNotEmpty ? tool.toolCallId : 'live_${turn.turnId}_tool_$t';
          currentSteps.add(ToolStep(id: stepId, tool: tool, timestamp: tool.startedAt));
        }
      }

      final hasCandidateLiveText = live.streamingText.trim().isNotEmpty && !hasActiveTools;

      if (hasCandidateLiveText) {
        emitGroup(isTrailing: true);
        output.add(LiveTailBlock(turnId: turn.turnId, text: live.streamingText, live: live));
      } else {
        final hadSteps = currentSteps.isNotEmpty;
        emitGroup(isTrailing: true);
        if (live.streamingText.isNotEmpty || !hadSteps) {
          output.add(LiveTailBlock(turnId: turn.turnId, text: live.streamingText, live: live));
        }
      }
    } else {
      emitGroup(isTrailing: true);
    }
    return;
  }

  // Legacy single-group flow (when showIntermediateAnswers is false)
  final steps = <StepItem>[];

  for (final entry in turn.nonUserEntries) {
    if (_isSubagentNotificationEntry(entry)) {
      steps.add(SubagentNotificationStep(id: '${entry.id}_subagent', entry: entry, timestamp: entry.timestamp));
      continue;
    }
    if (entry.role != 'assistant') continue;

    final asst = entry;
    if (asst.thinking != null && asst.thinking!.trim().isNotEmpty) {
      steps.add(
        ThinkingStep(
          id: '${asst.id}_thinking',
          text: asst.thinking!.trim(),
          isStreaming: false,
          timestamp: asst.timestamp,
        ),
      );
    }

    final toolsBeforeText = asst.toolCallsBeforeText;
    for (int t = 0; t < toolsBeforeText; t++) {
      final tool = asst.toolCalls[t];
      steps.add(
        ToolStep(
          id: tool.toolCallId.isNotEmpty ? tool.toolCallId : '${asst.id}_tool_$t',
          tool: tool,
          timestamp: tool.startedAt ?? asst.timestamp,
        ),
      );
    }

    if (asst.id != finalAssistantEntry?.id && asst.text.trim().isNotEmpty) {
      steps.add(IntermediateTextStep(id: '${asst.id}_text', text: asst.text, entry: asst, timestamp: asst.timestamp));
    }

    for (int t = toolsBeforeText; t < asst.toolCalls.length; t++) {
      final tool = asst.toolCalls[t];
      final stepId = tool.toolCallId.isNotEmpty ? tool.toolCallId : '${asst.id}_tool_$t';
      steps.add(ToolStep(id: stepId, tool: tool, timestamp: tool.startedAt ?? asst.timestamp));
    }
  }

  if (turn.isLastTurn && live.isRunning) {
    if (live.streamingThinking.trim().isNotEmpty) {
      steps.add(
        ThinkingStep(id: 'live_${turn.turnId}_thinking', text: live.streamingThinking.trim(), isStreaming: true),
      );
    }

    if (live.streamingText.trim().isNotEmpty && hasActiveTools) {
      steps.add(IntermediateTextStep(id: 'live_${turn.turnId}_text', text: live.streamingText));
    }

    if (hasActiveTools) {
      final existingToolIds = {for (final s in steps.whereType<ToolStep>()) s.toolCallId};
      for (int t = 0; t < live.activeToolCalls.length; t++) {
        final tool = live.activeToolCalls[t];
        if (tool.toolCallId.isNotEmpty && existingToolIds.contains(tool.toolCallId)) {
          continue;
        }
        final stepId = tool.toolCallId.isNotEmpty ? tool.toolCallId : 'live_${turn.turnId}_tool_$t';
        steps.add(ToolStep(id: stepId, tool: tool, timestamp: tool.startedAt));
      }
    }
  }

  final stepCount = steps
      .where((s) => s is ThinkingStep || s is ToolStep || s is SubagentNotificationStep || s is IntermediateTextStep)
      .length;
  final latestStep = steps.isNotEmpty ? steps.last : null;

  Duration? elapsed;
  final userTimestamp = turn.userEntry?.timestamp;
  if (userTimestamp != null && userTimestamp > 0) {
    int? endTimestamp;
    if (finalAssistantEntry != null && finalAssistantEntry.timestamp > 0) {
      endTimestamp = normalizeTimestampToMs(finalAssistantEntry.timestamp);
    } else {
      for (final s in steps.reversed) {
        if (s is ToolStep && s.startedAt != null && s.startedAt! > 0) {
          final startedMs = normalizeTimestampToMs(s.startedAt!);
          endTimestamp = startedMs + (s.durationMs ?? 0);
          break;
        } else if (s.timestamp != null && s.timestamp! > 0) {
          endTimestamp = normalizeTimestampToMs(s.timestamp!);
          break;
        }
      }
      if (endTimestamp == null && assistantEntries.isNotEmpty) {
        final last = assistantEntries.last;
        if (last.timestamp > 0) {
          endTimestamp = normalizeTimestampToMs(last.timestamp);
        }
      }
    }
    if (endTimestamp != null) {
      final startMs = normalizeTimestampToMs(userTimestamp);
      if (endTimestamp >= startMs) {
        elapsed = Duration(milliseconds: endTimestamp - startMs);
      }
    }
  }

  final hasToolError = steps.whereType<ToolStep>().any((s) => s.isError);
  final hasSubagentError = steps.whereType<SubagentNotificationStep>().any(
    (s) =>
        s.entry.metadata?['failed'] == true ||
        s.entry.metadata?['isError'] == true ||
        s.entry.metadata?['status'] == 'failed' ||
        s.entry.metadata?['status'] == 'error' ||
        s.entry.metadata?['sendError'] != null,
  );
  final lastStep = steps.isNotEmpty ? steps.last : null;
  final endedOnFailedTool = !isTurnRunning && finalAssistantEntry == null && lastStep is ToolStep && lastStep.isError;
  final legacyFailed =
      !isAborted && (hasTurnEndError || hasUserSendError || endedOnFailedTool || (turn.isLastTurn && live.hasError));
  final legacyError = hasToolError || hasSubagentError || hasGeneralError;

  final stepsGroup = StepsGroupBlock(
    groupId: 'steps_${turn.turnId}',
    turnId: turn.turnId,
    steps: steps,
    isRunning: turn.isLastTurn && live.isRunning,
    hasError: legacyError,
    aborted: isAborted,
    failed: legacyFailed,
    stepCount: stepCount,
    elapsed: elapsed,
    latestStep: latestStep,
  );

  final firstStepIdx = turn.nonUserEntries.indexWhere((e) => e.role == 'assistant' || _isSubagentNotificationEntry(e));

  if (firstStepIdx == -1) {
    if (steps.isNotEmpty || (turn.isLastTurn && live.isRunning)) {
      output.add(stepsGroup);
    }
    for (final m in turn.nonUserEntries) {
      if (!_isSubagentNotificationEntry(m)) {
        output.add(EntryBlock(m));
      }
    }
  } else {
    for (int i = 0; i < firstStepIdx; i++) {
      output.add(EntryBlock(turn.nonUserEntries[i]));
    }
    if (steps.isNotEmpty || (turn.isLastTurn && live.isRunning)) {
      output.add(stepsGroup);
    }

    for (int i = firstStepIdx; i < turn.nonUserEntries.length; i++) {
      final entry = turn.nonUserEntries[i];
      if (_isSubagentNotificationEntry(entry)) {
        continue;
      }
      if (entry.role != 'assistant') {
        output.add(EntryBlock(entry));
      } else if (entry.id == finalAssistantEntry?.id) {
        output.add(
          FinalTextBlock(
            entry: SessionEntry(
              id: entry.id,
              role: entry.role,
              text: entry.text,
              thinking: null,
              toolCalls: const [],
              timestamp: entry.timestamp,
              metadata: entry.metadata,
            ),
            turnId: turn.turnId,
          ),
        );
      }
    }
  }

  if (turn.isLastTurn && live.isRunning) {
    final hasCandidateLiveText = live.streamingText.trim().isNotEmpty && !hasActiveTools;
    if (hasCandidateLiveText) {
      output.add(LiveTailBlock(turnId: turn.turnId, text: live.streamingText, live: live));
    } else if (steps.isEmpty) {
      output.add(LiveTailBlock(turnId: turn.turnId, text: live.streamingText, live: live));
    }
  }
}

/// Normalizes a timestamp to milliseconds.
/// If timestamp is in seconds (10-digit Unix epoch, between ~2001 and ~2286), converts to ms.
int normalizeTimestampToMs(int ts) {
  if (ts >= 1000000000 && ts < 10000000000) {
    return ts * 1000;
  }
  return ts;
}

/// Test helper asserting 100% transcript coverage with NO LOSS.
///
/// Verifies that every input entry's text, thinking, and tool calls appear in
/// exactly one output block or step.
void assertTranscriptCoverage({required List<SessionEntry> inputEntries, required List<TranscriptBlock> blocks}) {
  final cleanInput = inputEntries.where((e) => !e.isJunkOrInternal).toList();
  for (final entry in cleanInput) {
    if (_isSubagentNotificationEntry(entry)) {
      final matchingEntryBlocks = blocks.whereType<EntryBlock>().where((b) => b.entry.id == entry.id).toList();
      final matchingSteps = blocks
          .whereType<StepsGroupBlock>()
          .expand((g) => g.steps)
          .whereType<SubagentNotificationStep>()
          .where((s) => s.entry.id == entry.id)
          .toList();
      final total = matchingEntryBlocks.length + matchingSteps.length;
      if (total != 1) {
        throw AssertionError(
          'Subagent notification entry ${entry.id} must appear exactly once as EntryBlock or SubagentNotificationStep, found $total',
        );
      }
      continue;
    }

    if (entry.role != 'assistant') {
      final matchingEntryBlocks = blocks.whereType<EntryBlock>().where((b) => b.entry.id == entry.id).toList();
      if (matchingEntryBlocks.length != 1) {
        throw AssertionError(
          'Non-assistant entry ${entry.id} (${entry.role}) must appear exactly once as EntryBlock, found ${matchingEntryBlocks.length}',
        );
      }
      continue;
    }

    // Assistant entry
    final entryBlockMatches = blocks.whereType<EntryBlock>().where((b) => b.entry.id == entry.id).toList();

    if (entryBlockMatches.isNotEmpty) {
      if (entryBlockMatches.length != 1) {
        throw AssertionError('Assistant entry ${entry.id} appears ${entryBlockMatches.length} times as EntryBlock');
      }
      // Cannot also be in a StepsGroupBlock or FinalTextBlock
      final groupedSteps = blocks
          .whereType<StepsGroupBlock>()
          .expand((g) => g.steps)
          .where((s) => s.id.startsWith(entry.id))
          .toList();
      final finalBlocks = blocks.whereType<FinalTextBlock>().where((f) => f.entry.id == entry.id).toList();
      final intermediateBlocks = blocks
          .whereType<IntermediateTextBlock>()
          .where((f) => f.entry.id == entry.id)
          .toList();
      if (groupedSteps.isNotEmpty || finalBlocks.isNotEmpty || intermediateBlocks.isNotEmpty) {
        throw AssertionError('Assistant entry ${entry.id} appears as EntryBlock AND in grouped steps/final text');
      }
      continue;
    }

    // Grouped assistant entry: verify thinking, tool calls, and text
    final allSteps = blocks.whereType<StepsGroupBlock>().expand((g) => g.steps).toList();
    final allFinalBlocks = blocks.whereType<FinalTextBlock>().toList();
    final allIntermediateBlocks = blocks.whereType<IntermediateTextBlock>().toList();

    // 1. Thinking coverage
    if (entry.thinking != null && entry.thinking!.trim().isNotEmpty) {
      final matchingThinking = allSteps.whereType<ThinkingStep>().where((s) => s.id == '${entry.id}_thinking').toList();
      if (matchingThinking.length != 1) {
        throw AssertionError(
          'Thinking of entry ${entry.id} must appear exactly once as ThinkingStep, found ${matchingThinking.length}',
        );
      }
      if (matchingThinking.first.text != entry.thinking!.trim()) {
        throw AssertionError('Thinking text mismatch for entry ${entry.id}');
      }
    }

    // 2. Tool calls coverage
    for (int t = 0; t < entry.toolCalls.length; t++) {
      final tool = entry.toolCalls[t];
      final expectedId = tool.toolCallId.isNotEmpty ? tool.toolCallId : '${entry.id}_tool_$t';
      final matchingTools = allSteps.whereType<ToolStep>().where((s) => s.id == expectedId).toList();
      if (matchingTools.length != 1) {
        throw AssertionError(
          'Tool call $expectedId of entry ${entry.id} must appear exactly once as ToolStep, found ${matchingTools.length}',
        );
      }
    }

    // 3. Text coverage
    if (entry.text.trim().isNotEmpty) {
      final matchingIntermediate = allSteps
          .whereType<IntermediateTextStep>()
          .where((s) => s.id == '${entry.id}_text')
          .toList();
      final matchingIntermediateBlock = allIntermediateBlocks.where((b) => b.entry.id == entry.id).toList();
      final matchingFinal = allFinalBlocks.where((f) => f.entry.id == entry.id).toList();

      final totalMatches = matchingIntermediate.length + matchingIntermediateBlock.length + matchingFinal.length;
      if (totalMatches != 1) {
        throw AssertionError(
          'Text of entry ${entry.id} must appear exactly once as IntermediateTextStep, IntermediateTextBlock, or FinalTextBlock, found $totalMatches',
        );
      }
      if (matchingIntermediate.isNotEmpty && matchingIntermediate.first.text != entry.text) {
        throw AssertionError('Intermediate text mismatch for entry ${entry.id}');
      }
      if (matchingIntermediateBlock.isNotEmpty && matchingIntermediateBlock.first.text != entry.text) {
        throw AssertionError('Intermediate block text mismatch for entry ${entry.id}');
      }
      if (matchingFinal.isNotEmpty && matchingFinal.first.text != entry.text) {
        throw AssertionError('Final text mismatch for entry ${entry.id}');
      }
    }
  }
}

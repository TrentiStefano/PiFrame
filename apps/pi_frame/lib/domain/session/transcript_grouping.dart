import 'session_state.dart';

/// Strategy for grouping intermediate assistant steps in a turn.
enum StepGroupingMode {
  /// Today's behavior: every entry is rendered as an individual block.
  off,

  /// Group a turn only when it contains model thinking (committed or streaming).
  withThinking,

  /// Group a turn whenever it has at least one intermediate step (thinking, tool call, intermediate text).
  always,
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
      streamingThinking.trim().isNotEmpty ||
      streamingText.trim().isNotEmpty ||
      activeToolCalls.isNotEmpty;

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
    final lastStopReason =
        lastEntry?.metadata?['stopReason']?.toString().toLowerCase();
    final lastCancelled = lastEntry?.metadata?['cancelled'] == true;

    final lastUserEntry =
        session.entries.reversed.where((e) => e.role == 'user').firstOrNull;
    final hasUserSendError = lastUserEntry?.metadata?['sendError'] != null;

    final hasActiveError = session.agentStatus.name.toLowerCase().contains('error') ||
        session.activeToolCalls.values.any((t) => t.isError) ||
        lastStopReason == 'error' ||
        hasUserSendError;

    final isAborted = lastStopReason == 'aborted' || lastCancelled;

    final isRunning = session.agentStatus.name == 'working' ||
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
      identical(this, other) ||
      other is EntryBlock &&
          runtimeType == other.runtimeType &&
          entry == other.entry;

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
  String toString() =>
      'StepsGroupBlock($groupId, stepCount: $stepCount, isRunning: $isRunning, hasError: $hasError)';
}

/// The final assistant response of a turn, rendered as text only.
/// Any thinking or tool calls associated with the original entry belong to the [StepsGroupBlock].
final class FinalTextBlock extends TranscriptBlock {
  /// Assistant entry stripped of thinking and tool calls so UI can render text bubble directly.
  final SessionEntry entry;

  /// Identifier of the turn.
  final String turnId;

  const FinalTextBlock({
    required this.entry,
    required this.turnId,
  });

  String get text => entry.text;

  @override
  String toString() => 'FinalTextBlock(entry: ${entry.id}, turnId: $turnId)';
}

/// Live streaming candidate final text or live stream marker during active running turns.
final class LiveTailBlock extends TranscriptBlock {
  final String turnId;
  final String text;
  final TranscriptLiveState live;

  const LiveTailBlock({
    required this.turnId,
    required this.text,
    required this.live,
  });

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

  const ThinkingStep({
    required this.id,
    required this.text,
    this.isStreaming = false,
    this.timestamp,
  });

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

  const ToolStep({
    required this.id,
    required this.tool,
    this.timestamp,
  });

  String get toolName => tool.toolName;
  String get toolCallId => tool.toolCallId;
  Map<String, dynamic> get args => tool.args;
  String get output => tool.output;
  bool get isError => tool.isError;
  bool get isRunning => tool.isRunning;
  int? get startedAt => tool.startedAt;
  int? get durationMs => tool.durationMs;
  Duration? get duration =>
      durationMs != null ? Duration(milliseconds: durationMs!) : null;

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

  const IntermediateTextStep({
    required this.id,
    required this.text,
    this.entry,
    this.timestamp,
  });

  @override
  String toString() => 'IntermediateTextStep($id, text: "$text")';
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

/// Pure function grouping transcript entries according to [mode] and [live] state.
///
/// Guarantees NO LOSS: every entry's text, thinking, and tool calls appear in exactly
/// one block/step.
List<TranscriptBlock> groupTranscript({
  required List<SessionEntry> entries,
  required StepGroupingMode mode,
  required TranscriptLiveState live,
}) {
  // Pre-filter internal/junk messages exactly like transcript_view
  final cleanEntries = entries.where((e) => !e.isJunkOrInternal).toList();

  // Mode off: return every entry as an EntryBlock, plus LiveTailBlock if live content exists.
  if (mode == StepGroupingMode.off) {
    final result = <TranscriptBlock>[
      for (final entry in cleanEntries) EntryBlock(entry),
    ];
    if (live.isRunning && (live.hasContent || live.streamingText.isNotEmpty)) {
      final lastUser =
          cleanEntries.reversed.where((e) => e.role == 'user').firstOrNull;
      final turnId = (lastUser?.metadata?['optimisticId'] as String?) ??
          lastUser?.id ??
          'turn_start';
      result.add(
        LiveTailBlock(
          turnId: turnId,
          text: live.streamingText,
          live: live,
        ),
      );
    }
    return result;
  }

  // Partition entries into turns (from user entry to next user entry).
  final turns = _partitionTurns(cleanEntries);
  final output = <TranscriptBlock>[];

  for (final turn in turns) {
    _processTurn(turn: turn, mode: mode, live: live, output: output);
  }

  return output;
}

List<_TurnData> _partitionTurns(List<SessionEntry> entries) {
  if (entries.isEmpty) {
    return const [
      _TurnData(
        turnId: 'turn_start',
        userEntry: null,
        nonUserEntries: [],
        isLastTurn: true,
      ),
    ];
  }

  final turns = <_TurnData>[];
  final userIndices = <int>[];
  for (int i = 0; i < entries.length; i++) {
    if (entries[i].role == 'user') {
      userIndices.add(i);
    }
  }

  if (userIndices.isEmpty) {
    turns.add(
      _TurnData(
        turnId: 'turn_start',
        userEntry: null,
        nonUserEntries: entries,
        isLastTurn: true,
      ),
    );
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
    final nextUserIdx =
        u + 1 < userIndices.length ? userIndices[u + 1] : entries.length;
    final isLast = u == userIndices.length - 1;
    final userEntry = entries[userIdx];
    final nonUserEntries = entries.sublist(userIdx + 1, nextUserIdx);

    final turnId =
        (userEntry.metadata?['optimisticId'] as String?) ?? userEntry.id;
    turns.add(
      _TurnData(
        turnId: turnId,
        userEntry: userEntry,
        nonUserEntries: nonUserEntries,
        isLastTurn: isLast,
      ),
    );
  }

  return turns;
}

void _processTurn({
  required _TurnData turn,
  required StepGroupingMode mode,
  required TranscriptLiveState live,
  required List<TranscriptBlock> output,
}) {
  final assistantEntries =
      turn.nonUserEntries.where((e) => e.role == 'assistant').toList();

  final hasCommittedThinking = assistantEntries.any(
    (e) => e.thinking != null && e.thinking!.trim().isNotEmpty,
  );
  final hasStreamingThinking =
      turn.isLastTurn && live.isRunning && live.streamingThinking.trim().isNotEmpty;
  final hasThinking = hasCommittedThinking || hasStreamingThinking;

  final hasCommittedTools =
      assistantEntries.any((e) => e.toolCalls.isNotEmpty);
  final hasActiveTools =
      turn.isLastTurn && live.isRunning && live.activeToolCalls.isNotEmpty;
  final hasTools = hasCommittedTools || hasActiveTools;

  // An intermediate text step exists if an assistant message with text is followed
  // by another assistant message or tool calls.
  bool hasCommittedIntermediateText = false;
  if (assistantEntries.length > 1) {
    hasCommittedIntermediateText =
        assistantEntries.sublist(0, assistantEntries.length - 1).any(
              (e) => e.text.trim().isNotEmpty,
            );
  }
  if (!hasCommittedIntermediateText && assistantEntries.isNotEmpty) {
    final last = assistantEntries.last;
    if (last.text.trim().isNotEmpty &&
        (last.toolCallsAfterText.isNotEmpty || hasActiveTools)) {
      hasCommittedIntermediateText = true;
    }
  }

  final hasIntermediateSteps =
      hasThinking || hasTools || hasCommittedIntermediateText;

  final bool shouldGroup;
  switch (mode) {
    case StepGroupingMode.off:
      shouldGroup = false;
      break;
    case StepGroupingMode.withThinking:
      shouldGroup = hasThinking;
      break;
    case StepGroupingMode.always:
      shouldGroup = hasIntermediateSteps;
      break;
  }

  // If not grouped, render turn in classic entry order
  if (!shouldGroup) {
    if (turn.userEntry != null) {
      output.add(EntryBlock(turn.userEntry!));
    }
    for (final entry in turn.nonUserEntries) {
      output.add(EntryBlock(entry));
    }
    if (turn.isLastTurn && live.isRunning && (live.hasContent || live.streamingText.isNotEmpty)) {
      output.add(
        LiveTailBlock(
          turnId: turn.turnId,
          text: live.streamingText,
          live: live,
        ),
      );
    }
    return;
  }

  // GROUPED TURN
  // 1. User entry (if any) is emitted first
  if (turn.userEntry != null) {
    output.add(EntryBlock(turn.userEntry!));
  }

  // Identify final assistant entry candidate (if any).
  // Trailing assistant entries with empty text and no tool calls (e.g. trailing thinking-only)
  // allow the immediately preceding assistant entry with non-empty text and no tool calls
  // to be chosen as final text.
  SessionEntry? finalAssistantEntry;
  if (!hasActiveTools &&
      !(turn.isLastTurn &&
          live.isRunning &&
          live.streamingText.trim().isNotEmpty)) {
    for (int i = assistantEntries.length - 1; i >= 0; i--) {
      final asst = assistantEntries[i];
      // Tool calls merged from an earlier text-less message ran before this
      // text; only tool calls after the text make it intermediate.
      if (asst.toolCallsAfterText.isNotEmpty) {
        break;
      }
      if (asst.text.trim().isNotEmpty) {
        final asstIdx = turn.nonUserEntries.indexOf(asst);
        final after = turn.nonUserEntries.sublist(asstIdx + 1);
        final everythingAfterHasNoTextAndNoTools = after.every(
          (e) => e.text.trim().isEmpty && e.toolCalls.isEmpty,
        );
        if (everythingAfterHasNoTextAndNoTools) {
          finalAssistantEntry = asst;
        }
        break;
      }
    }
  }

  // Collect step items in chronological order
  final steps = <StepItem>[];

  for (final asst in assistantEntries) {
    // 1. Thinking step
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

    // 2. Tool calls that ran before the text (merged from an earlier
    // text-less message), kept in chronological order.
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

    // 3. Text step (intermediate text)
    if (asst.id != finalAssistantEntry?.id && asst.text.trim().isNotEmpty) {
      steps.add(
        IntermediateTextStep(
          id: '${asst.id}_text',
          text: asst.text,
          entry: asst,
          timestamp: asst.timestamp,
        ),
      );
    }

    // 4. Tool calls after the text
    for (int t = toolsBeforeText; t < asst.toolCalls.length; t++) {
      final tool = asst.toolCalls[t];
      final stepId = tool.toolCallId.isNotEmpty
          ? tool.toolCallId
          : '${asst.id}_tool_$t';
      steps.add(
        ToolStep(
          id: stepId,
          tool: tool,
          timestamp: tool.startedAt ?? asst.timestamp,
        ),
      );
    }
  }

  // Live items for running active turn
  if (turn.isLastTurn && live.isRunning) {
    if (live.streamingThinking.trim().isNotEmpty) {
      steps.add(
        ThinkingStep(
          id: 'live_${turn.turnId}_thinking',
          text: live.streamingThinking.trim(),
          isStreaming: true,
        ),
      );
    }

    if (live.streamingText.trim().isNotEmpty && hasActiveTools) {
      // Live text was followed by active tool calls -> intermediate
      steps.add(
        IntermediateTextStep(
          id: 'live_${turn.turnId}_text',
          text: live.streamingText,
        ),
      );
    }

    if (hasActiveTools) {
      final existingToolIds = {
        for (final s in steps.whereType<ToolStep>()) s.toolCallId,
      };
      for (int t = 0; t < live.activeToolCalls.length; t++) {
        final tool = live.activeToolCalls[t];
        if (tool.toolCallId.isNotEmpty && existingToolIds.contains(tool.toolCallId)) {
          continue;
        }
        final stepId = tool.toolCallId.isNotEmpty
            ? tool.toolCallId
            : 'live_${turn.turnId}_tool_$t';
        steps.add(
          ToolStep(
            id: stepId,
            tool: tool,
            timestamp: tool.startedAt,
          ),
        );
      }
    }
  }

  final stepCount =
      steps.where((s) => s is ThinkingStep || s is ToolStep).length;
  final latestStep = steps.isNotEmpty ? steps.last : null;

  // Compute elapsed time from turn start to last step or final entry
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

  // Error and abort detection
  final hasToolError = steps.whereType<ToolStep>().any((s) => s.isError);
  final hasEntryError = turn.nonUserEntries.any(
    (e) =>
        e.metadata?['sendError'] != null ||
        e.metadata?['stopReason'] == 'error' ||
        (e.role == 'bashExecution' &&
            e.metadata?['exitCode'] is int &&
            e.metadata!['exitCode'] != 0),
  );
  final hasUserSendError = turn.userEntry?.metadata?['sendError'] != null;
  // Pi retries failed requests, so only the last assistant message decides
  // whether the turn ended in error.
  final lastAssistant = assistantEntries.lastOrNull;
  final hasTurnEndError =
      lastAssistant?.metadata?['stopReason'] == 'error' ||
      turn.nonUserEntries.any((e) => e.metadata?['sendError'] != null);
  final hasEntryAbort = turn.nonUserEntries.any(
    (e) =>
        e.metadata?['stopReason'] == 'aborted' ||
        e.metadata?['cancelled'] == true,
  );

  final isAborted = hasEntryAbort || (turn.isLastTurn && live.aborted);
  // The turn failed only if the turn itself ended in error. Failed tool calls
  // (e.g. a non-zero bash exit the agent then worked around) do not fail a
  // turn that reached its final answer; they only flag it with an error icon.
  // A settled turn that has no final answer and stopped right on a failed
  // tool call also ended in failure.
  final isTurnRunning = turn.isLastTurn && live.isRunning;
  final lastStep = steps.isNotEmpty ? steps.last : null;
  final endedOnFailedTool = !isTurnRunning &&
      finalAssistantEntry == null &&
      lastStep is ToolStep &&
      lastStep.isError;
  final isFailed = !isAborted &&
      (hasTurnEndError ||
          hasUserSendError ||
          endedOnFailedTool ||
          (turn.isLastTurn && live.hasError));
  final hasError = hasToolError ||
      hasEntryError ||
      hasUserSendError ||
      isAborted ||
      (turn.isLastTurn && live.hasError);

  final stepsGroup = StepsGroupBlock(
    groupId: 'steps_${turn.turnId}',
    turnId: turn.turnId,
    steps: steps,
    isRunning: turn.isLastTurn && live.isRunning,
    hasError: hasError,
    aborted: isAborted,
    failed: isFailed,
    stepCount: stepCount,
    elapsed: elapsed,
    latestStep: latestStep,
  );

  // Position StepsGroupBlock and milestones
  // Ordering rule: milestones before the first step appear before the group;
  // group is positioned where the first step appears; mid-turn milestones appear
  // after the group; final text appears after mid-turn milestones.
  final firstStepIdx = turn.nonUserEntries.indexWhere((e) => e.role == 'assistant');

  if (firstStepIdx == -1) {
    // All steps are live / no assistant entries yet
    output.add(stepsGroup);
    for (final m in turn.nonUserEntries) {
      output.add(EntryBlock(m));
    }
  } else {
    // Milestones prior to the first step
    for (int i = 0; i < firstStepIdx; i++) {
      output.add(EntryBlock(turn.nonUserEntries[i]));
    }

    // Steps group placed at first step position
    output.add(stepsGroup);

    // Remaining entries: milestones and final text
    for (int i = firstStepIdx; i < turn.nonUserEntries.length; i++) {
      final entry = turn.nonUserEntries[i];
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

  // Trailing streaming candidate final text
  if (turn.isLastTurn && live.isRunning) {
    final hasCandidateLiveText =
        live.streamingText.trim().isNotEmpty && !hasActiveTools;
    if (hasCandidateLiveText) {
      output.add(
        LiveTailBlock(
          turnId: turn.turnId,
          text: live.streamingText,
          live: live,
        ),
      );
    } else if (steps.isEmpty) {
      // Group was empty but live stream is active
      output.add(
        LiveTailBlock(
          turnId: turn.turnId,
          text: live.streamingText,
          live: live,
        ),
      );
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
void assertTranscriptCoverage({
  required List<SessionEntry> inputEntries,
  required List<TranscriptBlock> blocks,
}) {
  final cleanInput = inputEntries.where((e) => !e.isJunkOrInternal).toList();
  for (final entry in cleanInput) {
    if (entry.role != 'assistant') {
      final matchingEntryBlocks = blocks
          .whereType<EntryBlock>()
          .where((b) => b.entry.id == entry.id)
          .toList();
      if (matchingEntryBlocks.length != 1) {
        throw AssertionError(
          'Non-assistant entry ${entry.id} (${entry.role}) must appear exactly once as EntryBlock, found ${matchingEntryBlocks.length}',
        );
      }
      continue;
    }

    // Assistant entry
    final entryBlockMatches = blocks
        .whereType<EntryBlock>()
        .where((b) => b.entry.id == entry.id)
        .toList();

    if (entryBlockMatches.isNotEmpty) {
      if (entryBlockMatches.length != 1) {
        throw AssertionError(
          'Assistant entry ${entry.id} appears ${entryBlockMatches.length} times as EntryBlock',
        );
      }
      // Cannot also be in a StepsGroupBlock or FinalTextBlock
      final groupedSteps = blocks
          .whereType<StepsGroupBlock>()
          .expand((g) => g.steps)
          .where((s) => s.id.startsWith(entry.id))
          .toList();
      final finalBlocks = blocks
          .whereType<FinalTextBlock>()
          .where((f) => f.entry.id == entry.id)
          .toList();
      if (groupedSteps.isNotEmpty || finalBlocks.isNotEmpty) {
        throw AssertionError(
          'Assistant entry ${entry.id} appears as EntryBlock AND in grouped steps/final text',
        );
      }
      continue;
    }

    // Grouped assistant entry: verify thinking, tool calls, and text
    final allSteps =
        blocks.whereType<StepsGroupBlock>().expand((g) => g.steps).toList();
    final allFinalBlocks = blocks.whereType<FinalTextBlock>().toList();

    // 1. Thinking coverage
    if (entry.thinking != null && entry.thinking!.trim().isNotEmpty) {
      final matchingThinking = allSteps
          .whereType<ThinkingStep>()
          .where((s) => s.id == '${entry.id}_thinking')
          .toList();
      if (matchingThinking.length != 1) {
        throw AssertionError(
          'Thinking of entry ${entry.id} must appear exactly once as ThinkingStep, found ${matchingThinking.length}',
        );
      }
      if (matchingThinking.first.text != entry.thinking!.trim()) {
        throw AssertionError(
          'Thinking text mismatch for entry ${entry.id}',
        );
      }
    }

    // 2. Tool calls coverage
    for (int t = 0; t < entry.toolCalls.length; t++) {
      final tool = entry.toolCalls[t];
      final expectedId =
          tool.toolCallId.isNotEmpty ? tool.toolCallId : '${entry.id}_tool_$t';
      final matchingTools = allSteps
          .whereType<ToolStep>()
          .where((s) => s.id == expectedId)
          .toList();
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
      final matchingFinal = allFinalBlocks
          .where((f) => f.entry.id == entry.id)
          .toList();

      final totalMatches = matchingIntermediate.length + matchingFinal.length;
      if (totalMatches != 1) {
        throw AssertionError(
          'Text of entry ${entry.id} must appear exactly once as IntermediateTextStep or FinalTextBlock, found $totalMatches',
        );
      }
      if (matchingIntermediate.isNotEmpty &&
          matchingIntermediate.first.text != entry.text) {
        throw AssertionError(
          'Intermediate text mismatch for entry ${entry.id}',
        );
      }
      if (matchingFinal.isNotEmpty && matchingFinal.first.text != entry.text) {
        throw AssertionError(
          'Final text mismatch for entry ${entry.id}',
        );
      }
    }
  }
}

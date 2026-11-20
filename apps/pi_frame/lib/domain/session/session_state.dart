import 'agent_status.dart';

class ToolExecutionState {
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> args;
  final String output;
  final bool isRunning;
  final bool isError;
  final int? durationMs;
  final int? startedAt;

  const ToolExecutionState({
    required this.toolCallId,
    required this.toolName,
    this.args = const {},
    this.output = '',
    this.isRunning = false,
    this.isError = false,
    this.durationMs,
    this.startedAt,
  });

  int? elapsedMsAt(int timestamp) {
    if (!isRunning || startedAt == null) return durationMs;
    final elapsed = timestamp - startedAt!;
    return elapsed < 0 ? 0 : elapsed;
  }

  ToolExecutionState copyWith({
    String? output,
    bool? isRunning,
    bool? isError,
    int? durationMs,
    int? startedAt,
  }) {
    return ToolExecutionState(
      toolCallId: toolCallId,
      toolName: toolName,
      args: args,
      output: output ?? this.output,
      isRunning: isRunning ?? this.isRunning,
      isError: isError ?? this.isError,
      durationMs: durationMs ?? this.durationMs,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

class SessionEntry {
  final String id;
  final String role; // 'user', 'assistant', 'system', 'bashExecution', 'custom', 'branchSummary', 'compactionSummary'
  final String text;
  final String? thinking;
  final List<ToolExecutionState> toolCalls;
  final int timestamp;
  final Map<String, dynamic>? metadata;

  const SessionEntry({
    required this.id,
    required this.role,
    required this.text,
    this.thinking,
    this.toolCalls = const [],
    required this.timestamp,
    this.metadata,
  });

  SessionEntry copyWith({
    String? id,
    String? role,
    String? text,
    String? thinking,
    List<ToolExecutionState>? toolCalls,
    int? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return SessionEntry(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      thinking: thinking ?? this.thinking,
      toolCalls: toolCalls ?? this.toolCalls,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isJunkOrInternal {
    if (role == 'system' || role == 'toolResult' || role == 'tool') return true;
    if (role == 'custom' && metadata?['display'] == false) return true;
    if (role == 'assistant' && isInternalOrJunkMessageText(text)) return true;
    return false;
  }

  /// Number of leading [toolCalls] that ran before [text] was written.
  ///
  /// A text-less assistant message (tool calls only) is merged into the next
  /// assistant message that has text, so the tool calls of the earlier message
  /// precede the text. The remaining tool calls belong to the message that
  /// carries the text and come after it.
  int get toolCallsBeforeText {
    final raw = metadata?[toolsBeforeTextKey];
    if (raw is! int || raw <= 0) return 0;
    return raw > toolCalls.length ? toolCalls.length : raw;
  }

  /// Tool calls that ran after [text]; an assistant text is final only if
  /// this is empty.
  List<ToolExecutionState> get toolCallsAfterText =>
      toolCalls.sublist(toolCallsBeforeText);
}

/// Returns the turn-ending metadata (`stopReason`, `errorMessage`) of an
/// assistant [message] that ended in error or was aborted, or null.
Map<String, dynamic>? terminalStopMetadata(Map message) {
  final stopReason = message['stopReason']?.toString();
  if (stopReason != 'error' && stopReason != 'aborted') return null;
  final errorMessage = message['errorMessage']?.toString();
  return {'stopReason': stopReason, 'errorMessage': ?errorMessage};
}

/// Records the [terminal] stop of an empty assistant message on [entries].
/// Returns null when there is nothing to record.
///
/// With a previous assistant entry the stop is kept on it. A provider error
/// that ends the turn before any reply marks the user message as failed, so the
/// transcript shows the error and a retry instead of a silent missing reply.
List<SessionEntry>? applyTerminalStop(
  List<SessionEntry> entries,
  Map<String, dynamic> terminal,
) {
  if (entries.isEmpty) return null;
  final last = entries.last;
  if (last.role == 'assistant') {
    return List<SessionEntry>.from(entries)
      ..[entries.length - 1] = last.copyWith(
        metadata: {...?last.metadata, ...terminal},
      );
  }
  final error = terminal['errorMessage']?.toString() ?? '';
  if (last.role != 'user' ||
      terminal['stopReason'] != 'error' ||
      error.isEmpty) {
    return null;
  }
  return List<SessionEntry>.from(entries)
    ..[entries.length - 1] = last.copyWith(
      metadata: {...?last.metadata, 'sendError': error},
    );
}

/// Metadata key that records how many leading tool calls precede the text.
const toolsBeforeTextKey = 'toolsBeforeText';

/// Merges an assistant [entry] that has text into the preceding text-less
/// assistant entry [prev] (tool calls and/or thinking only), so the classic
/// transcript shows them as one bubble.
///
/// The merged entry records in [toolsBeforeTextKey] that the tool calls of
/// [prev] ran before the text, so step grouping can keep the chronological
/// order and still recognise the text as the final answer.
SessionEntry mergeTextIntoTextlessAssistant(
  SessionEntry prev,
  SessionEntry entry,
) {
  final mergedTools = List<ToolExecutionState>.from(prev.toolCalls);
  for (final t in entry.toolCalls) {
    if (!mergedTools.any((e) => e.toolCallId == t.toolCallId)) {
      mergedTools.add(t);
    }
  }
  final prevThinking = prev.thinking?.trim();
  final entryThinking = entry.thinking?.trim();
  final combinedThinking =
      prevThinking != null &&
          entryThinking != null &&
          prevThinking != entryThinking
      ? '$prevThinking\n\n$entryThinking'
      : (prevThinking ?? entryThinking);
  return SessionEntry(
    id: prev.id,
    role: 'assistant',
    text: entry.text,
    thinking: combinedThinking,
    toolCalls: mergedTools,
    timestamp: prev.timestamp,
    metadata: {
      ...?prev.metadata,
      ...?entry.metadata,
      toolsBeforeTextKey: prev.toolCalls.length,
    },
  );
}

bool isInternalOrJunkMessageText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  // 1. Pure (exit 0, no output)
  if (trimmed == '(exit 0, no output)') {
    return true;
  }
  // 3. Git CRLF replacement warnings
  final lines = trimmed
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isNotEmpty &&
      lines.every(
        (l) =>
            l.startsWith('warning:') &&
            l.contains('LF will be replaced by CRLF'),
      )) {
    return true;
  }
  return false;
}

class SessionState {
  final String sessionId;
  final String? sessionName;
  final String cwd;
  final bool readOnly;
  final String? readOnlyReason;
  final AgentStatus agentStatus;
  final int? runStartedAt;
  final List<SessionEntry> entries;
  final Map<int, String> streamingTextBlocks;
  final Map<int, String> streamingThinkingBlocks;
  final Map<String, ToolExecutionState> activeToolCalls;
  final Map<String, String> toolOutputs;
  final List<String> steeringQueue;
  final List<String> followUpQueue;
  final List<Map<String, dynamic>> pendingUiRequests;
  final String? currentModel;
  final String? currentModelProvider;
  final String? currentModelId;
  final String? currentThinkingLevel;
  final Map<String, dynamic>? usage;
  final Map<String, dynamic>? sessionStats;
  final Map<String, String> extensionStatuses;
  final int? contextWindowOverride;
  final double compactionReservePercent;
  final bool autoCompaction;
  final int lastAppliedSeq;
  final bool hasMoreHistory;
  final int? totalTranscriptEntries;

  const SessionState({
    required this.sessionId,
    this.sessionName,
    required this.cwd,
    this.readOnly = false,
    this.readOnlyReason,
    this.agentStatus = AgentStatus.settled,
    this.runStartedAt,
    this.entries = const [],
    this.streamingTextBlocks = const {},
    this.streamingThinkingBlocks = const {},
    this.activeToolCalls = const {},
    this.toolOutputs = const {},
    this.steeringQueue = const [],
    this.followUpQueue = const [],
    this.pendingUiRequests = const [],
    this.currentModel,
    this.currentModelProvider,
    this.currentModelId,
    this.currentThinkingLevel,
    this.usage,
    this.sessionStats,
    this.extensionStatuses = const {},
    this.contextWindowOverride,
    this.compactionReservePercent = 2.5,
    this.autoCompaction = true,
    this.lastAppliedSeq = 0,
    this.hasMoreHistory = false,
    this.totalTranscriptEntries,
  });

  String get currentStreamingText => streamingTextBlocks.values.join();

  String get currentStreamingThinking => streamingThinkingBlocks.values.join();

  bool matchesModel(Map<String, dynamic> model) {
    final provider = currentModelProvider;
    if (provider != null &&
        provider.isNotEmpty &&
        model['provider']?.toString() != provider) {
      return false;
    }
    if (currentModelId != null) {
      return model['id']?.toString() == currentModelId;
    }
    return model['id']?.toString() == currentModel ||
        model['name']?.toString() == currentModel;
  }

  bool get isStreaming =>
      streamingTextBlocks.isNotEmpty ||
      streamingThinkingBlocks.isNotEmpty ||
      activeToolCalls.values.any((t) => t.isRunning) ||
      agentStatus == AgentStatus.working;

  SessionState copyWith({
    String? sessionName,
    String? cwd,
    bool? readOnly,
    String? readOnlyReason,
    AgentStatus? agentStatus,
    int? runStartedAt,
    bool clearRunStartedAt = false,
    List<SessionEntry>? entries,
    Map<int, String>? streamingTextBlocks,
    Map<int, String>? streamingThinkingBlocks,
    Map<String, ToolExecutionState>? activeToolCalls,
    Map<String, String>? toolOutputs,
    List<String>? steeringQueue,
    List<String>? followUpQueue,
    List<Map<String, dynamic>>? pendingUiRequests,
    String? currentModel,
    String? currentModelProvider,
    String? currentModelId,
    String? currentThinkingLevel,
    Map<String, dynamic>? usage,
    Map<String, dynamic>? sessionStats,
    Map<String, String>? extensionStatuses,
    int? contextWindowOverride,
    bool clearContextWindowOverride = false,
    double? compactionReservePercent,
    bool? autoCompaction,
    int? lastAppliedSeq,
    bool? hasMoreHistory,
    int? totalTranscriptEntries,
  }) {
    return SessionState(
      sessionId: sessionId,
      sessionName: sessionName ?? this.sessionName,
      cwd: cwd ?? this.cwd,
      readOnly: readOnly ?? this.readOnly,
      readOnlyReason: readOnlyReason ?? this.readOnlyReason,
      agentStatus: agentStatus ?? this.agentStatus,
      runStartedAt: clearRunStartedAt ? null : (runStartedAt ?? this.runStartedAt),
      entries: entries ?? this.entries,
      streamingTextBlocks: streamingTextBlocks ?? this.streamingTextBlocks,
      streamingThinkingBlocks:
          streamingThinkingBlocks ?? this.streamingThinkingBlocks,
      activeToolCalls: activeToolCalls ?? this.activeToolCalls,
      toolOutputs: toolOutputs ?? this.toolOutputs,
      steeringQueue: steeringQueue ?? this.steeringQueue,
      followUpQueue: followUpQueue ?? this.followUpQueue,
      pendingUiRequests: pendingUiRequests ?? this.pendingUiRequests,
      currentModel: currentModel ?? this.currentModel,
      currentModelProvider: currentModelProvider ?? this.currentModelProvider,
      currentModelId: currentModelId ?? this.currentModelId,
      currentThinkingLevel: currentThinkingLevel ?? this.currentThinkingLevel,
      usage: usage ?? this.usage,
      sessionStats: sessionStats ?? this.sessionStats,
      extensionStatuses: extensionStatuses ?? this.extensionStatuses,
      contextWindowOverride: clearContextWindowOverride
          ? null
          : contextWindowOverride ?? this.contextWindowOverride,
      compactionReservePercent:
          compactionReservePercent ?? this.compactionReservePercent,
      autoCompaction: autoCompaction ?? this.autoCompaction,
      lastAppliedSeq: lastAppliedSeq ?? this.lastAppliedSeq,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      totalTranscriptEntries:
          totalTranscriptEntries ?? this.totalTranscriptEntries,
    );
  }
}

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

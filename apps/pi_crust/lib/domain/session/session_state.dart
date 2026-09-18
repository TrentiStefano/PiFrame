import 'agent_status.dart';

class SessionEntry {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  final String text;
  final String? thinking;
  final List<Map<String, dynamic>> toolCalls;
  final int timestamp;

  const SessionEntry({
    required this.id,
    required this.role,
    required this.text,
    this.thinking,
    this.toolCalls = const [],
    required this.timestamp,
  });
}

class SessionState {
  final String sessionId;
  final String? sessionName;
  final String cwd;
  final AgentStatus agentStatus;
  final List<SessionEntry> entries;
  final Map<int, String> streamingTextBlocks;
  final Map<int, String> streamingThinkingBlocks;
  final Map<String, String> toolOutputs;
  final List<String> steeringQueue;
  final List<String> followUpQueue;
  final List<Map<String, dynamic>> pendingUiRequests;
  final String? currentModel;
  final String? currentThinkingLevel;
  final Map<String, dynamic>? usage;
  final int lastAppliedSeq;

  const SessionState({
    required this.sessionId,
    this.sessionName,
    required this.cwd,
    this.agentStatus = AgentStatus.settled,
    this.entries = const [],
    this.streamingTextBlocks = const {},
    this.streamingThinkingBlocks = const {},
    this.toolOutputs = const {},
    this.steeringQueue = const [],
    this.followUpQueue = const [],
    this.pendingUiRequests = const [],
    this.currentModel,
    this.currentThinkingLevel,
    this.usage,
    this.lastAppliedSeq = 0,
  });

  String get currentStreamingText =>
      streamingTextBlocks.values.join();

  String get currentStreamingThinking =>
      streamingThinkingBlocks.values.join();

  bool get isStreaming =>
      streamingTextBlocks.isNotEmpty || agentStatus == AgentStatus.working;

  SessionState copyWith({
    String? sessionId,
    String? sessionName,
    String? cwd,
    AgentStatus? agentStatus,
    List<SessionEntry>? entries,
    Map<int, String>? streamingTextBlocks,
    Map<int, String>? streamingThinkingBlocks,
    Map<String, String>? toolOutputs,
    List<String>? steeringQueue,
    List<String>? followUpQueue,
    List<Map<String, dynamic>>? pendingUiRequests,
    String? currentModel,
    String? currentThinkingLevel,
    Map<String, dynamic>? usage,
    int? lastAppliedSeq,
  }) {
    return SessionState(
      sessionId: sessionId ?? this.sessionId,
      sessionName: sessionName ?? this.sessionName,
      cwd: cwd ?? this.cwd,
      agentStatus: agentStatus ?? this.agentStatus,
      entries: entries ?? this.entries,
      streamingTextBlocks: streamingTextBlocks ?? this.streamingTextBlocks,
      streamingThinkingBlocks: streamingThinkingBlocks ?? this.streamingThinkingBlocks,
      toolOutputs: toolOutputs ?? this.toolOutputs,
      steeringQueue: steeringQueue ?? this.steeringQueue,
      followUpQueue: followUpQueue ?? this.followUpQueue,
      pendingUiRequests: pendingUiRequests ?? this.pendingUiRequests,
      currentModel: currentModel ?? this.currentModel,
      currentThinkingLevel: currentThinkingLevel ?? this.currentThinkingLevel,
      usage: usage ?? this.usage,
      lastAppliedSeq: lastAppliedSeq ?? this.lastAppliedSeq,
    );
  }
}

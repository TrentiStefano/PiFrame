import 'agent_status.dart';
import 'session_state.dart';

String _contentText(dynamic content, String type) {
  if (content is String && type == 'text') return content;
  if (content is! List) return '';
  return content.whereType<Map>().where((b) => b['type'] == type)
      .map((b) => b[type]?.toString() ?? '').join();
}

ToolExecutionState _tool(Map<String, dynamic> tool) => ToolExecutionState(
  toolCallId: tool['toolCallId']?.toString() ?? '',
  toolName: tool['toolName']?.toString() ?? '',
  args: Map<String, dynamic>.from(tool['args'] as Map? ?? {}),
  output: tool['output']?.toString() ?? '',
  isRunning: tool['isRunning'] == true,
  isError: tool['isError'] == true,
  durationMs: (tool['durationMs'] as num?)?.toInt(),
);

SessionState applySessionSnapshot(String sessionId, int seq, Map<String, dynamic> payload) {
  final meta = payload['session'] as Map? ?? {};
  final runtime = payload['runtime'] as Map? ?? {};
  final transcript = payload['transcript'] as Map? ?? {};
  final live = payload['liveMessage'] as Map? ?? {};
  final queue = runtime['queue'] as Map? ?? {};
  final entries = <SessionEntry>[];
  for (final raw in (transcript['entries'] as List? ?? []).whereType<Map>()) {
    final message = raw['message'] is Map ? raw['message'] as Map : raw;
    final role = message['role']?.toString() ?? 'assistant';
    if (role == 'system' || role == 'toolResult' || role == 'tool') continue;
    final text = _contentText(message['content'] ?? message['text'], 'text');
    final thinking = _contentText(message['content'], 'thinking');
    if (isInternalOrJunkMessageText(text)) continue;
    if (text.trim().isEmpty && thinking.trim().isEmpty) continue;

    final timestamp = message['timestamp'] ?? raw['timestamp'];
    entries.add(SessionEntry(
      id: (raw['id'] ?? message['id'])?.toString() ?? 'snapshot_${entries.length}',
      role: role,
      text: text,
      thinking: thinking.isNotEmpty ? thinking : null,
      timestamp: timestamp is num ? timestamp.toInt() :
          DateTime.tryParse(timestamp?.toString() ?? '')?.millisecondsSinceEpoch ?? 0,
    ));
  }
  final tools = <String, ToolExecutionState>{};
  for (final raw in (payload['activeTools'] as List? ?? []).whereType<Map>()) {
    final tool = _tool(Map<String, dynamic>.from(raw));
    tools[tool.toolCallId] = tool;
  }
  final status = switch (runtime['status']) {
    'working' => AgentStatus.working,
    'retrying' => AgentStatus.retrying,
    'compacting' => AgentStatus.compacting,
    'awaiting_user' => AgentStatus.awaitingUser,
    'worker_error' => AgentStatus.workerError,
    _ => AgentStatus.settled,
  };
  final text = _contentText(live['content'], 'text');
  final thinking = _contentText(live['content'], 'thinking');
  final model = runtime['model'];
  return SessionState(
    sessionId: sessionId,
    sessionName: meta['name']?.toString(),
    cwd: meta['cwd']?.toString() ?? '',
    readOnly: meta['readOnly'] == true,
    readOnlyReason: meta['readOnlyReason']?.toString(),
    agentStatus: status,
    entries: entries,
    streamingTextBlocks: text.isEmpty ? {} : {0: text},
    streamingThinkingBlocks: thinking.isEmpty ? {} : {0: thinking},
    activeToolCalls: tools,
    steeringQueue: (queue['steering'] as List? ?? []).map((e) => e.toString()).toList(),
    followUpQueue: (queue['followUp'] as List? ?? []).map((e) => e.toString()).toList(),
    pendingUiRequests: (payload['pendingUiRequests'] as List? ?? []).whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e)).toList(),
    currentModel: model is Map ? (model['name'] ?? model['id'])?.toString() : null,
    currentThinkingLevel: runtime['thinkingLevel']?.toString(),
    usage: Map<String, dynamic>.from(payload['usage'] as Map? ?? {}),
    lastAppliedSeq: seq,
  );
}

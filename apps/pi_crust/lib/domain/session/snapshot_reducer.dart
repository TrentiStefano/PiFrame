import 'agent_status.dart';
import 'session_state.dart';

String _contentText(dynamic content, String type) {
  if (content is String && type == 'text') return content;
  if (content is! List) return '';
  final buffer = StringBuffer();
  for (final b in content) {
    if (b is Map && b['type'] == type) {
      final val = b[type]?.toString();
      if (val != null) buffer.write(val);
    }
  }
  return buffer.toString();
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

  // Pre-collect outputs from toolResult messages keyed by toolCallId
  final toolResults = <String, String>{};
  for (final raw in (transcript['entries'] as List? ?? []).whereType<Map>()) {
    final message = raw['message'] is Map ? raw['message'] as Map : raw;
    final role = message['role']?.toString() ?? '';
    if (role == 'toolResult' || role == 'tool') {
      final callId = (message['toolCallId'] ?? message['tool_call_id'] ?? raw['toolCallId'])?.toString();
      final out = message['result']?.toString() ??
          message['output']?.toString() ??
          (message['content'] is String ? message['content'] as String : null);
      if (callId != null && out != null) {
        toolResults[callId] = out;
      }
    }
  }

  for (final raw in (transcript['entries'] as List? ?? []).whereType<Map>()) {
    final message = raw['message'] is Map ? raw['message'] as Map : raw;
    final role = message['role']?.toString() ?? 'assistant';
    if (role == 'system' || role == 'toolResult' || role == 'tool') continue;
    final text = _contentText(message['content'] ?? message['text'], 'text');
    final thinking = _contentText(message['content'], 'thinking');

    // Extract tool calls from message
    final entryToolCalls = <ToolExecutionState>[];
    if (message['toolCalls'] is List) {
      for (final t in (message['toolCalls'] as List).whereType<Map>()) {
        entryToolCalls.add(_tool(Map<String, dynamic>.from(t)));
      }
    }
    if (message['content'] is List) {
      for (final b in (message['content'] as List).whereType<Map>()) {
        if (b['type'] == 'tool_call' || b['type'] == 'tool_use') {
          final callId = (b['id'] ?? b['toolCallId'])?.toString() ?? '';
          final name = (b['name'] ?? b['toolName'])?.toString() ?? '';
          final args = Map<String, dynamic>.from((b['args'] ?? b['input']) as Map? ?? {});
          final out = toolResults[callId] ?? b['output']?.toString() ?? '';
          entryToolCalls.add(ToolExecutionState(
            toolCallId: callId,
            toolName: name,
            args: args,
            output: out,
            isRunning: false,
          ));
        }
      }
    }

    if (isInternalOrJunkMessageText(text)) continue;
    if (text.trim().isEmpty && thinking.trim().isEmpty && entryToolCalls.isEmpty) continue;

    final timestamp = message['timestamp'] ?? raw['timestamp'];
    final entry = SessionEntry(
      id: (raw['id'] ?? message['id'])?.toString() ?? 'snapshot_${entries.length}',
      role: role,
      text: text,
      thinking: thinking.isNotEmpty ? thinking : null,
      toolCalls: entryToolCalls,
      timestamp: timestamp is num ? timestamp.toInt() :
          DateTime.tryParse(timestamp?.toString() ?? '')?.millisecondsSinceEpoch ?? 0,
    );

    // If previous entry was an assistant entry with empty text and this is an assistant entry with text,
    // merge them together into a unified turn
    if (entries.isNotEmpty &&
        entries.last.role == 'assistant' &&
        entries.last.text.isEmpty &&
        role == 'assistant' &&
        text.isNotEmpty) {
      final prev = entries.removeLast();
      final mergedTools = List<ToolExecutionState>.from(prev.toolCalls);
      for (final t in entry.toolCalls) {
        if (!mergedTools.any((e) => e.toolCallId == t.toolCallId)) {
          mergedTools.add(t);
        }
      }
      final combinedThinking = prev.thinking != null &&
              entry.thinking != null &&
              prev.thinking != entry.thinking
          ? '${prev.thinking}\n\n${entry.thinking}'
          : (prev.thinking ?? entry.thinking);
      entries.add(SessionEntry(
        id: prev.id,
        role: 'assistant',
        text: text,
        thinking: combinedThinking,
        toolCalls: mergedTools,
        timestamp: prev.timestamp,
      ));
    } else {
      entries.add(entry);
    }
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
    currentModel: model is Map
        ? (model['name'] ?? model['id'])?.toString()
        : (model is String && model.isNotEmpty ? model : null),
    currentThinkingLevel: runtime['thinkingLevel']?.toString(),
    usage: Map<String, dynamic>.from(payload['usage'] as Map? ?? {}),
    lastAppliedSeq: seq,
  );
}

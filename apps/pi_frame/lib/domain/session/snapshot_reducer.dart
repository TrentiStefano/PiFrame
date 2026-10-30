import 'agent_status.dart';
import 'attachment_model.dart';
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
  startedAt: (tool['startedAt'] as num?)?.toInt(),
);

List<SessionEntry> parseSessionEntries(Iterable<Map> rawList) {
  final entries = <SessionEntry>[];

  // Pre-collect outputs from toolResult messages keyed by toolCallId
  final toolResults = <String, String>{};
  final toolErrors = <String, bool>{};
  for (final raw in rawList) {
    final message = raw['message'] is Map ? raw['message'] as Map : raw;
    final role = message['role']?.toString() ?? '';
    if (role == 'toolResult' || role == 'tool') {
      final callId =
          (message['toolCallId'] ??
                  message['tool_call_id'] ??
                  raw['toolCallId'])
              ?.toString();
      final out =
          message['result']?.toString() ??
          message['output']?.toString() ??
          _contentText(message['content'], 'text');
      if (callId != null) {
        toolResults[callId] = out;
        toolErrors[callId] = message['isError'] == true;
      }
    }
  }

  for (final raw in rawList) {
    final message = raw['message'] is Map ? raw['message'] as Map : raw;
    final role = message['role']?.toString() ?? 'assistant';
    if (role == 'system' || role == 'toolResult' || role == 'tool') continue;

    final timestampRaw = message['timestamp'] ?? raw['timestamp'];
    final timestamp = timestampRaw is num
        ? timestampRaw.toInt()
        : DateTime.tryParse(timestampRaw?.toString() ?? '')
                  ?.millisecondsSinceEpoch ??
              0;
    final entryId =
        (raw['id'] ?? message['id'])?.toString() ??
        'snapshot_${entries.length}';

    if (role == 'bashExecution') {
      final command =
          (message['command'] ?? message['cmd'])?.toString() ?? '!bash';
      final output =
          (message['output'] ?? message['result'] ?? '')?.toString() ?? '';
      final exitCode = message['exitCode'] is num
          ? (message['exitCode'] as num).toInt()
          : null;
      final cancelled = message['cancelled'] == true;
      final truncated = message['truncated'] == true;
      entries.add(
        SessionEntry(
          id: entryId,
          role: 'bashExecution',
          text: output,
          timestamp: timestamp,
          metadata: {
            'command': command,
            'exitCode': exitCode,
            'cancelled': cancelled,
            'truncated': truncated,
          },
        ),
      );
      continue;
    }

    if (role == 'branchSummary') {
      final summary = (message['summary'] ?? message['text'])?.toString() ?? '';
      final fromId =
          (message['fromId'] ?? message['from_id'])?.toString() ?? '';
      entries.add(
        SessionEntry(
          id: entryId,
          role: 'branchSummary',
          text: summary,
          timestamp: timestamp,
          metadata: {'fromId': fromId},
        ),
      );
      continue;
    }

    if (role == 'compactionSummary') {
      final summary = (message['summary'] ?? message['text'])?.toString() ?? '';
      final tokensBefore =
          (message['tokensBefore'] ?? message['tokens_before'] as num?)
              ?.toInt();
      entries.add(
        SessionEntry(
          id: entryId,
          role: 'compactionSummary',
          text: summary,
          timestamp: timestamp,
          metadata: {'tokensBefore': tokensBefore},
        ),
      );
      continue;
    }

    if (role == 'custom') {
      final customType =
          (message['customType'] ?? message['custom_type'] ?? 'custom')
              ?.toString() ??
          'custom';
      final display = message['display'] != false;
      String customText = '';
      if (message['content'] is String) {
        customText = message['content'] as String;
      } else if (message['content'] is List) {
        customText = (message['content'] as List)
            .whereType<Map>()
            .where((b) => b['type'] == 'text')
            .map((b) => b['text']?.toString() ?? '')
            .join();
      }
      entries.add(
        SessionEntry(
          id: entryId,
          role: 'custom',
          text: customText,
          timestamp: timestamp,
          metadata: {
            'customType': customType,
            'display': display,
            'details': message['details'],
          },
        ),
      );
      continue;
    }

    var text = _contentText(message['content'] ?? message['text'], 'text');
    final thinking = _contentText(message['content'], 'thinking');

    // Extract image blocks into ChatAttachment tags if present
    if (message['content'] is List) {
      final attachments = <ChatAttachment>[];
      for (final block in (message['content'] as List).whereType<Map>()) {
        if (block['type'] == 'image') {
          final data = block['data']?.toString() ?? '';
          final mimeType = block['mimeType']?.toString() ?? 'image/png';
          if (data.isNotEmpty) {
            attachments.add(
              ChatAttachment(
                id: 'att_${attachments.length}',
                name:
                    'image_${attachments.length + 1}.${mimeType.split('/').last}',
                type: AttachmentType.image,
                pathOrUrl: 'data:$mimeType;base64,$data',
              ),
            );
          }
        }
      }
      if (attachments.isNotEmpty && !text.contains('<!--pi-attachments:')) {
        text = '$text\n${encodeAttachmentsTag(attachments)}'.trim();
      }
    }

    // Extract tool calls from message
    final entryToolCalls = <ToolExecutionState>[];
    if (message['toolCalls'] is List) {
      for (final t in (message['toolCalls'] as List).whereType<Map>()) {
        entryToolCalls.add(_tool(Map<String, dynamic>.from(t)));
      }
    }
    if (message['content'] is List) {
      for (final b in (message['content'] as List).whereType<Map>()) {
        if (b['type'] == 'toolCall' ||
            b['type'] == 'tool_call' ||
            b['type'] == 'tool_use') {
          final callId = (b['id'] ?? b['toolCallId'])?.toString() ?? '';
          final name = (b['name'] ?? b['toolName'])?.toString() ?? '';
          final args = Map<String, dynamic>.from(
            (b['arguments'] ?? b['args'] ?? b['input']) as Map? ?? {},
          );
          final out = toolResults[callId] ?? b['output']?.toString() ?? '';
          final hasError =
              (toolErrors[callId] == true) || (b['isError'] == true);
          entryToolCalls.add(
            ToolExecutionState(
              toolCallId: callId,
              toolName: name,
              args: args,
              output: out,
              isRunning: false,
              isError: hasError,
              startedAt: (b['startedAt'] as num?)?.toInt(),
              durationMs: (b['durationMs'] as num?)?.toInt(),
            ),
          );
        }
      }
    }

    if (isInternalOrJunkMessageText(text)) continue;
    if (text.trim().isEmpty &&
        thinking.trim().isEmpty &&
        entryToolCalls.isEmpty) {
      continue;
    }

    final entryModel = message['model'] ?? message['modelId'];
    final entryUsage = message['usage'];
    final entry = SessionEntry(
      id: entryId,
      role: role,
      text: text,
      thinking: thinking.isNotEmpty ? thinking : null,
      toolCalls: entryToolCalls,
      timestamp: timestamp,
      metadata: {'model': ?entryModel, 'usage': ?entryUsage},
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
      final prevThinking = prev.thinking?.trim();
      final entryThinking = entry.thinking?.trim();
      final combinedThinking =
          prevThinking != null &&
              entryThinking != null &&
              prevThinking != entryThinking
          ? '$prevThinking\n\n$entryThinking'
          : (prevThinking ?? entryThinking);
      entries.add(
        SessionEntry(
          id: prev.id,
          role: 'assistant',
          text: text,
          thinking: combinedThinking,
          toolCalls: mergedTools,
          timestamp: prev.timestamp,
          metadata: {
            if (prev.metadata != null) ...prev.metadata!,
            if (entry.metadata != null) ...entry.metadata!,
          },
        ),
      );
    } else {
      entries.add(entry);
    }
  }
  return entries;
}

SessionState applySessionSnapshot(
  String sessionId,
  int seq,
  Map<String, dynamic> payload,
) {
  final meta = payload['session'] as Map? ?? {};
  final runtime = payload['runtime'] as Map? ?? {};
  final transcript = payload['transcript'] as Map? ?? {};
  final live = payload['liveMessage'] as Map? ?? {};
  final queue = runtime['queue'] as Map? ?? {};
  final entries = parseSessionEntries(
    (transcript['entries'] as List? ?? []).whereType<Map>(),
  );
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
  final rawUsage = Map<String, dynamic>.from(payload['usage'] as Map? ?? {});

  // Aggregate usage from transcript entries if payload['usage'] is empty or missing cost
  double aggregatedCost = 0.0;
  bool foundEntryCost = false;
  int aggregatedTotalTokens = 0;
  int aggregatedInputTokens = 0;
  int aggregatedOutputTokens = 0;
  bool foundEntryTokens = false;

  for (final raw in (transcript['entries'] as List? ?? []).whereType<Map>()) {
    final message = raw['message'] is Map ? raw['message'] as Map : raw;
    final u = message['usage'] is Map
        ? message['usage'] as Map
        : (raw['usage'] is Map ? raw['usage'] as Map : null);
    if (u != null) {
      if (u['cost'] != null) {
        final c = u['cost'];
        final num? val = (c is Map ? (c['total'] ?? c['amount']) : c) as num?;
        if (val != null) {
          aggregatedCost += val.toDouble();
          foundEntryCost = true;
        }
      }
      final tokens = u['tokens'] is Map ? u['tokens'] as Map : null;
      if (tokens != null) {
        if (tokens['total'] is num) {
          aggregatedTotalTokens = (tokens['total'] as num).toInt();
          foundEntryTokens = true;
        }
        if (tokens['input'] is num) {
          aggregatedInputTokens = (tokens['input'] as num).toInt();
        }
        if (tokens['output'] is num) {
          aggregatedOutputTokens = (tokens['output'] as num).toInt();
        }
      } else if (u['totalTokens'] is num) {
        aggregatedTotalTokens = (u['totalTokens'] as num).toInt();
        foundEntryTokens = true;
      }
    }
  }

  if (rawUsage['cost'] == null && foundEntryCost) {
    rawUsage['cost'] = aggregatedCost;
  }
  if (rawUsage['totalTokens'] == null && foundEntryTokens) {
    rawUsage['totalTokens'] = aggregatedTotalTokens;
    rawUsage['inputTokens'] = aggregatedInputTokens;
    rawUsage['outputTokens'] = aggregatedOutputTokens;
  }

  Map<String, dynamic>? initialStats;
  if (rawUsage.isNotEmpty) {
    initialStats = {
      if (rawUsage['cost'] != null)
        'cost': rawUsage['cost'] is Map
            ? (rawUsage['cost']['total'] ?? rawUsage['cost']['amount'])
            : rawUsage['cost'],
      if (rawUsage['totalTokens'] != null)
        'tokens': {
          'total': rawUsage['totalTokens'],
          'input': rawUsage['inputTokens'],
          'output': rawUsage['outputTokens'],
        },
    };
  }

  return SessionState(
    sessionId: sessionId,
    sessionName: meta['name']?.toString(),
    cwd: meta['cwd']?.toString() ?? '',
    readOnly: meta['readOnly'] == true,
    readOnlyReason: meta['readOnlyReason']?.toString(),
    agentStatus: status,
    runStartedAt: (runtime['runStartedAt'] as num?)?.toInt(),
    entries: entries,
    streamingTextBlocks: text.isEmpty ? {} : {0: text},
    streamingThinkingBlocks: thinking.isEmpty ? {} : {0: thinking},
    activeToolCalls: tools,
    steeringQueue: (queue['steering'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    followUpQueue: (queue['followUp'] as List? ?? [])
        .map((e) => e.toString())
        .toList(),
    pendingUiRequests: (payload['pendingUiRequests'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
    currentModel: model is Map
        ? (model['name'] ?? model['id'])?.toString()
        : (model is String && model.isNotEmpty ? model : null),
    currentThinkingLevel: runtime['thinkingLevel']?.toString(),
    contextWindowOverride: runtime.containsKey('contextWindowOverride')
        ? (runtime['contextWindowOverride'] as num?)?.toInt()
        : (meta['contextWindowOverride'] as num?)?.toInt(),
    compactionReservePercent:
        (runtime['compactionReservePercent'] as num?)?.toDouble() ?? 2.5,
    autoCompaction: runtime['autoCompaction'] != false,
    usage: rawUsage,
    sessionStats: initialStats,
    lastAppliedSeq: seq,
    hasMoreHistory: transcript['hasMore'] as bool? ?? false,
    totalTranscriptEntries: (transcript['totalEntries'] as num?)?.toInt(),
  );
}

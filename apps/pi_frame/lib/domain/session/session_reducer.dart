import 'package:pi_frame_protocol/pi_frame_protocol.dart';

import 'agent_status.dart';
import 'attachment_model.dart';
import 'session_state.dart';

SessionState reduceSessionState(SessionState current, PcpEvent event) {
  // Deduplicate on sequence number if assigned
  if (event.seq > 0 && event.seq <= current.lastAppliedSeq) {
    return current;
  }

  final nextSeq = event.seq > current.lastAppliedSeq
      ? event.seq
      : current.lastAppliedSeq;

  switch (event) {
    case SessionStatusEvent(:final status):
      final normalizedStatus = status.toLowerCase();
      final AgentStatus newStatus;
      switch (normalizedStatus) {
        case 'working':
          newStatus = AgentStatus.working;
          break;
        case 'retrying':
          newStatus = AgentStatus.retrying;
          break;
        case 'compacting':
          newStatus = AgentStatus.compacting;
          break;
        case 'awaiting_user':
          newStatus = AgentStatus.awaitingUser;
          break;
        case 'worker_error':
        case 'error':
          newStatus = AgentStatus.workerError;
          break;
        case 'settled':
        case 'idle':
        default:
          newStatus = AgentStatus.settled;
          break;
      }

      if (newStatus == AgentStatus.settled) {
        final updatedTools = current.activeToolCalls.map(
          (k, v) => MapEntry(k, v.isRunning ? v.copyWith(isRunning: false) : v),
        );
        return current.copyWith(
          agentStatus: AgentStatus.settled,
          activeToolCalls: updatedTools,
          streamingTextBlocks: const {},
          streamingThinkingBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      return current.copyWith(
        agentStatus: newStatus,
        lastAppliedSeq: nextSeq,
      );

    case RunStartedEvent():
      return current.copyWith(
        agentStatus: AgentStatus.working,
        lastAppliedSeq: nextSeq,
      );

    case RunEndedEvent(:final willRetry):
      return current.copyWith(
        agentStatus: willRetry
            ? AgentStatus.retrying
            : (current.activeToolCalls.values.any((t) => t.isRunning) ||
                    current.streamingTextBlocks.isNotEmpty ||
                    current.streamingThinkingBlocks.isNotEmpty
                ? current.agentStatus
                : AgentStatus.settled),
        lastAppliedSeq: nextSeq,
      );

    case TurnEndedEvent():
      return current.copyWith(
        streamingTextBlocks: const {},
        lastAppliedSeq: nextSeq,
      );

    case RunSettledEvent():
      var updatedEntries = current.entries;
      final liveThinking = current.currentStreamingThinking.trim();
      final liveText = current.currentStreamingText.trim();
      if (current.activeToolCalls.isNotEmpty ||
          liveThinking.isNotEmpty ||
          (liveText.isNotEmpty &&
              !isInternalOrJunkMessageText(current.currentStreamingText))) {
        if (updatedEntries.isNotEmpty &&
            updatedEntries.last.role == 'assistant') {
          final last = updatedEntries.last;
          final mergedTools = List<ToolExecutionState>.from(last.toolCalls);
          for (final t in current.activeToolCalls.values) {
            final completedT = t.isRunning ? t.copyWith(isRunning: false) : t;
            if (!mergedTools.any((e) => e.toolCallId == completedT.toolCallId)) {
              mergedTools.add(completedT);
            }
          }
          final newThinking = liveThinking.isNotEmpty ? liveThinking : null;
          final lastThinking = last.thinking?.trim();
          final combinedThinking = lastThinking != null &&
                  newThinking != null &&
                  lastThinking != newThinking
              ? '$lastThinking\n\n$newThinking'
              : (lastThinking ?? newThinking);
          final updatedLast = SessionEntry(
            id: last.id,
            role: last.role,
            text: last.text.isNotEmpty
                ? last.text
                : current.currentStreamingText,
            thinking: combinedThinking,
            toolCalls: mergedTools,
            timestamp: last.timestamp,
            metadata: last.metadata,
          );
          updatedEntries = List<SessionEntry>.from(updatedEntries)
            ..[updatedEntries.length - 1] = updatedLast;
        } else {
          updatedEntries = List<SessionEntry>.from(updatedEntries)
            ..add(SessionEntry(
              id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
              role: 'assistant',
              text: current.currentStreamingText,
              thinking: liveThinking.isNotEmpty ? liveThinking : null,
              toolCalls: current.activeToolCalls.values
                  .map((t) => t.isRunning ? t.copyWith(isRunning: false) : t)
                  .toList(),
              timestamp: DateTime.now().millisecondsSinceEpoch,
              metadata: {
                if (current.currentModel != null) 'model': current.currentModel,
              },
            ));
        }
      }
      return current.copyWith(
        agentStatus: AgentStatus.settled,
        entries: updatedEntries,
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
        lastAppliedSeq: nextSeq,
      );

    case TextDeltaEvent(:final contentIndex, :final delta):
      final updated = Map<int, String>.from(current.streamingTextBlocks);
      updated[contentIndex] = (updated[contentIndex] ?? '') + delta;
      return current.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: updated,
        lastAppliedSeq: nextSeq,
      );

    case ThinkingDeltaEvent(:final contentIndex, :final delta):
      final updated = Map<int, String>.from(current.streamingThinkingBlocks);
      updated[contentIndex] = (updated[contentIndex] ?? '') + delta;
      return current.copyWith(
        agentStatus: AgentStatus.working,
        streamingThinkingBlocks: updated,
        lastAppliedSeq: nextSeq,
      );

    case MessageCompletedEvent(:final message):
      final msg = message ?? {};
      final role = (msg['role'] as String?) ?? 'assistant';
      if (role == 'system' || role == 'toolResult' || role == 'tool') {
        if (role == 'toolResult' || role == 'tool') {
          final toolCallId =
              (msg['toolCallId'] ?? msg['tool_call_id'] ?? msg['id'])?.toString();
          String? output = msg['result']?.toString() ?? msg['output']?.toString();
          if (output == null) {
            if (msg['content'] is String) {
              output = msg['content'] as String;
            } else if (msg['content'] is List) {
              output = (msg['content'] as List)
                  .whereType<Map>()
                  .where((b) => b['type'] == 'text')
                  .map((b) => b['text']?.toString() ?? '')
                  .join();
            }
          }
          final isError = msg['isError'] == true;
          final resolvedOutput = output ?? '';
          if (toolCallId != null) {
            final nextOutputs = Map<String, String>.from(current.toolOutputs);
            nextOutputs[toolCallId] = resolvedOutput;
            final updatedTools =
                Map<String, ToolExecutionState>.from(current.activeToolCalls);
            if (updatedTools.containsKey(toolCallId)) {
              final existing = updatedTools[toolCallId]!;
              updatedTools[toolCallId] = existing.copyWith(
                output: resolvedOutput.isNotEmpty ? resolvedOutput : existing.output,
                isRunning: false,
                isError: isError || existing.isError,
              );
            }
            // Also update any existing entries that contain this tool call
            final updatedEntries = current.entries.map((entry) {
              if (entry.toolCalls.any((t) => t.toolCallId == toolCallId)) {
                final updatedToolCalls = entry.toolCalls.map((t) {
                  if (t.toolCallId == toolCallId) {
                    return t.copyWith(
                      output: resolvedOutput.isNotEmpty ? resolvedOutput : t.output,
                      isRunning: false,
                      isError: isError || t.isError,
                    );
                  }
                  return t;
                }).toList();
                return entry.copyWith(toolCalls: updatedToolCalls);
              }
              return entry;
            }).toList();

            return current.copyWith(
              activeToolCalls: updatedTools,
              toolOutputs: nextOutputs,
              entries: updatedEntries,
              lastAppliedSeq: nextSeq,
            );
          }
        }
        return current.copyWith(lastAppliedSeq: nextSeq);
      }

      if (role == 'bashExecution') {
        final command = (msg['command'] ?? msg['cmd'])?.toString() ?? '!bash';
        final output = (msg['output'] ?? msg['result'] ?? '')?.toString() ?? '';
        final exitCode = msg['exitCode'] is num ? (msg['exitCode'] as num).toInt() : null;
        final cancelled = msg['cancelled'] == true;
        final truncated = msg['truncated'] == true;
        final entry = SessionEntry(
          id: (msg['id'] ?? 'bash_${current.entries.length}').toString(),
          role: 'bashExecution',
          text: output,
          timestamp: (msg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'command': command,
            'exitCode': exitCode,
            'cancelled': cancelled,
            'truncated': truncated,
          },
        );
        return current.copyWith(
          entries: [...current.entries, entry],
          streamingTextBlocks: const {},
          streamingThinkingBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      if (role == 'branchSummary') {
        final summary = (msg['summary'] ?? msg['text'])?.toString() ?? '';
        final fromId = (msg['fromId'] ?? msg['from_id'])?.toString() ?? '';
        final entry = SessionEntry(
          id: (msg['id'] ?? 'branch_${current.entries.length}').toString(),
          role: 'branchSummary',
          text: summary,
          timestamp: (msg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          metadata: {'fromId': fromId},
        );
        return current.copyWith(
          entries: [...current.entries, entry],
          streamingTextBlocks: const {},
          streamingThinkingBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      if (role == 'compactionSummary') {
        final summary = (msg['summary'] ?? msg['text'])?.toString() ?? '';
        final tokensBefore = (msg['tokensBefore'] ?? msg['tokens_before'] as num?)?.toInt();
        final entry = SessionEntry(
          id: (msg['id'] ?? 'compact_${current.entries.length}').toString(),
          role: 'compactionSummary',
          text: summary,
          timestamp: (msg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          metadata: {'tokensBefore': tokensBefore},
        );
        return current.copyWith(
          entries: [...current.entries, entry],
          streamingTextBlocks: const {},
          streamingThinkingBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      if (role == 'custom') {
        final customType = (msg['customType'] ?? msg['custom_type'] ?? 'custom')?.toString() ?? 'custom';
        final display = msg['display'] != false;
        String text = '';
        if (msg['content'] is String) {
          text = msg['content'] as String;
        } else if (msg['content'] is List) {
          text = (msg['content'] as List)
              .whereType<Map>()
              .where((b) => b['type'] == 'text')
              .map((b) => b['text']?.toString() ?? '')
              .join();
        }
        final entry = SessionEntry(
          id: (msg['id'] ?? 'custom_${current.entries.length}').toString(),
          role: 'custom',
          text: text,
          timestamp: (msg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'customType': customType,
            'display': display,
            'details': msg['details'],
          },
        );
        return current.copyWith(
          entries: [...current.entries, entry],
          streamingTextBlocks: const {},
          streamingThinkingBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      // Extract text content if message contains content blocks
      String text = '';
      if (msg['content'] is String) {
        text = msg['content'] as String;
      } else if (msg['content'] is List) {
        for (final block in (msg['content'] as List)) {
          if (block is Map && block['type'] == 'text') {
            text += (block['text'] as String?) ?? '';
          }
        }
      }
      if (text.isEmpty && current.currentStreamingText.isNotEmpty) {
        text = current.currentStreamingText;
      }

      // If content has image blocks, convert to ChatAttachment:
      if (msg['content'] is List) {
        final attachments = <ChatAttachment>[];
        for (final block in (msg['content'] as List).whereType<Map>()) {
          if (block['type'] == 'image') {
            final data = block['data']?.toString() ?? '';
            final mimeType = block['mimeType']?.toString() ?? 'image/png';
            if (data.isNotEmpty) {
              attachments.add(ChatAttachment(
                id: 'att_${attachments.length}',
                name: 'image_${attachments.length + 1}.${mimeType.split('/').last}',
                type: AttachmentType.image,
                pathOrUrl: 'data:$mimeType;base64,$data',
              ));
            }
          }
        }
        if (attachments.isNotEmpty && !text.contains('<!--pi-attachments:')) {
          text = '$text\n${encodeAttachmentsTag(attachments)}'.trim();
        }
      }

      // Extract thinking from streaming blocks or message content blocks
      String? thinking = current.currentStreamingThinking.trim().isNotEmpty
          ? current.currentStreamingThinking.trim()
          : (msg['thinking']?.toString().trim().isNotEmpty == true ? msg['thinking'].toString().trim() : null);
      if (thinking == null && msg['content'] is List) {
        final tb = (msg['content'] as List)
            .whereType<Map>()
            .where((b) => b['type'] == 'thinking' || b['type'] == 'thought')
            .map((b) => (b['thinking'] ?? b['thought'] ?? b['text'])?.toString() ?? '')
            .join()
            .trim();
        if (tb.isNotEmpty) thinking = tb;
      }

      // Extract tool calls from activeToolCalls and message content blocks
      final Map<String, ToolExecutionState> turnTools =
          Map<String, ToolExecutionState>.from(current.activeToolCalls);
      if (msg['content'] is List) {
        for (final b in (msg['content'] as List).whereType<Map>()) {
          if (b['type'] == 'tool_call' || b['type'] == 'tool_use') {
            final callId = (b['id'] ?? b['toolCallId'])?.toString() ??
                'tc_${turnTools.length}';
            final name = (b['name'] ?? b['toolName'])?.toString() ?? '';
            final args = Map<String, dynamic>.from(
              (b['args'] ?? b['input']) as Map? ?? {},
            );
            if (!turnTools.containsKey(callId)) {
              turnTools[callId] = ToolExecutionState(
                toolCallId: callId,
                toolName: name,
                args: args,
                output: current.toolOutputs[callId] ?? '',
                isRunning: false,
              );
            }
          }
        }
      }
      if (msg['toolCalls'] is List) {
        for (final b in (msg['toolCalls'] as List).whereType<Map>()) {
          final callId = (b['id'] ?? b['toolCallId'])?.toString() ??
              'tc_${turnTools.length}';
          final name = (b['name'] ?? b['toolName'])?.toString() ?? '';
          final args = Map<String, dynamic>.from(
            (b['args'] ?? b['input']) as Map? ?? {},
          );
          if (!turnTools.containsKey(callId)) {
            turnTools[callId] = ToolExecutionState(
              toolCallId: callId,
              toolName: name,
              args: args,
              output: b['output']?.toString() ?? current.toolOutputs[callId] ?? '',
              isRunning: b['isRunning'] == true,
              isError: b['isError'] == true,
            );
          }
        }
      }

      if (isInternalOrJunkMessageText(text)) {
        return current.copyWith(
          streamingTextBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      if (text.trim().isEmpty &&
          (thinking == null || thinking.trim().isEmpty) &&
          turnTools.isEmpty) {
        return current.copyWith(
          streamingTextBlocks: const {},
          lastAppliedSeq: nextSeq,
        );
      }

      final id =
          (msg['id'] as String?) ??
          'msg_${DateTime.now().millisecondsSinceEpoch}';

      final entryModel = msg['model'] ?? msg['modelId'] ?? current.currentModel;
      final entryUsage = msg['usage'];
      final entry = SessionEntry(
        id: id,
        role: role,
        text: text,
        thinking: thinking,
        toolCalls: turnTools.values.toList(),
        timestamp:
            (msg['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        metadata: {
          'model': ?entryModel,
          'usage': ?entryUsage,
        },
      );

      final isTaskNotif = text.contains('<task-notification>');
      if (isTaskNotif) {
        final nextEntries = List<SessionEntry>.from(current.entries)..add(entry);
        return current.copyWith(
          entries: nextEntries,
          lastAppliedSeq: nextSeq,
        );
      }

      final nextEntries = List<SessionEntry>.from(current.entries);
      if (role == 'assistant' &&
          nextEntries.isNotEmpty &&
          nextEntries.last.role == 'assistant' &&
          nextEntries.last.text.isEmpty &&
          text.isNotEmpty) {
        final prev = nextEntries.removeLast();
        final mergedTools = List<ToolExecutionState>.from(prev.toolCalls);
        for (final t in entry.toolCalls) {
          if (!mergedTools.any((e) => e.toolCallId == t.toolCallId)) {
            mergedTools.add(t);
          }
        }
        final prevThinking = prev.thinking?.trim();
        final entryThinking = entry.thinking?.trim();
        final combinedThinking = prevThinking != null &&
                entryThinking != null &&
                prevThinking != entryThinking
            ? '$prevThinking\n\n$entryThinking'
            : (prevThinking ?? entryThinking);
        nextEntries.add(SessionEntry(
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
        ));
      } else {
        nextEntries.add(entry);
      }

      return current.copyWith(
        entries: nextEntries,
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
        lastAppliedSeq: nextSeq,
      );

    case ToolStartedEvent(:final toolCallId, :final toolName, :final args):
      final nextActive = Map<String, ToolExecutionState>.from(
        current.activeToolCalls,
      );
      nextActive[toolCallId] = ToolExecutionState(
        toolCallId: toolCallId,
        toolName: toolName,
        args: args,
        isRunning: true,
      );
      return current.copyWith(
        activeToolCalls: nextActive,
        lastAppliedSeq: nextSeq,
      );

    case ToolProgressEvent(
      :final toolCallId,
      :final toolName,
      :final partialResult,
    ):
      // Cumulative replacement rule: partialResult is NOT a delta
      final outputStr = partialResult?.toString() ?? '';
      final nextOutputs = Map<String, String>.from(current.toolOutputs);
      nextOutputs[toolCallId] = outputStr;

      final nextActive = Map<String, ToolExecutionState>.from(
        current.activeToolCalls,
      );
      final existing = nextActive[toolCallId];
      if (existing != null) {
        nextActive[toolCallId] = existing.copyWith(output: outputStr);
      } else {
        nextActive[toolCallId] = ToolExecutionState(
          toolCallId: toolCallId,
          toolName: toolName,
          output: outputStr,
          isRunning: true,
        );
      }

      return current.copyWith(
        activeToolCalls: nextActive,
        toolOutputs: nextOutputs,
        lastAppliedSeq: nextSeq,
      );

    case ToolCompletedEvent(
      :final toolCallId,
      :final toolName,
      :final result,
      :final isError,
      :final durationMs,
    ):
      final outputStr = result?.toString() ?? '';
      final nextOutputs = Map<String, String>.from(current.toolOutputs);
      nextOutputs[toolCallId] = outputStr;

      final nextActive = Map<String, ToolExecutionState>.from(
        current.activeToolCalls,
      );
      final existing = nextActive[toolCallId];
      if (existing != null) {
        nextActive[toolCallId] = existing.copyWith(
          output: outputStr.isNotEmpty ? outputStr : existing.output,
          isRunning: false,
          isError: isError,
          durationMs: durationMs,
        );
      } else {
        nextActive[toolCallId] = ToolExecutionState(
          toolCallId: toolCallId,
          toolName: toolName,
          output: outputStr,
          isRunning: false,
          isError: isError,
          durationMs: durationMs,
        );
      }

      // Also update any existing entries that contain this tool call
      final updatedEntries = current.entries.map((entry) {
        if (entry.toolCalls.any((t) => t.toolCallId == toolCallId)) {
          final updatedToolCalls = entry.toolCalls.map((t) {
            if (t.toolCallId == toolCallId) {
              return t.copyWith(
                output: outputStr.isNotEmpty ? outputStr : t.output,
                isRunning: false,
                isError: isError || t.isError,
                durationMs: durationMs ?? t.durationMs,
              );
            }
            return t;
          }).toList();
          return entry.copyWith(toolCalls: updatedToolCalls);
        }
        return entry;
      }).toList();

      return current.copyWith(
        activeToolCalls: nextActive,
        toolOutputs: nextOutputs,
        entries: updatedEntries,
        lastAppliedSeq: nextSeq,
      );

    case QueueChangedEvent(:final steering, :final followUp):
      return current.copyWith(
        steeringQueue: List<String>.from(steering),
        followUpQueue: List<String>.from(followUp),
        lastAppliedSeq: nextSeq,
      );

    case UsageUpdatedEvent(:final usage):
      final nextStats = Map<String, dynamic>.from(current.sessionStats ?? const {});
      if (usage.containsKey('cost')) {
        final c = usage['cost'];
        final num? rawCost = c is Map
            ? (c['total'] as num? ?? c['amount'] as num?)
            : (c is num ? c : null);
        if (rawCost != null) {
          final existingCost = (nextStats['cost'] as num?)?.toDouble() ?? 0.0;
          if (rawCost > existingCost) {
            nextStats['cost'] = rawCost;
          }
        }
      }
      if (usage.containsKey('totalTokens')) {
        final currentTotal = ((nextStats['tokens'] as Map?)?['total'] as num?)?.toInt() ?? 0;
        final newTotal = (usage['totalTokens'] as num?)?.toInt() ?? 0;
        if (newTotal >= currentTotal) {
          nextStats['tokens'] = {
            'total': newTotal,
            'input': usage['input'] ?? usage['inputTokens'] ?? 0,
            'output': usage['output'] ?? usage['outputTokens'] ?? 0,
          };
        }
      }
      if (usage.containsKey('byModel')) {
        nextStats['byModel'] = usage['byModel'];
        nextStats['models'] = usage['byModel'];
      } else if (usage.containsKey('models')) {
        nextStats['models'] = usage['models'];
        nextStats['byModel'] = usage['models'];
      }
      return current.copyWith(
        usage: usage,
        sessionStats: nextStats.isNotEmpty ? nextStats : current.sessionStats,
        lastAppliedSeq: nextSeq,
      );

    case UiStatusEvent(:final statusKey, :final statusText):
      final statuses = Map<String, String>.from(current.extensionStatuses);
      if (statusText == null || statusText.isEmpty) {
        statuses.remove(statusKey);
      } else {
        statuses[statusKey] = statusText;
      }
      return current.copyWith(
        extensionStatuses: statuses,
        lastAppliedSeq: nextSeq,
      );

    case CompactionStartedEvent():
      return current.copyWith(
        agentStatus: AgentStatus.compacting,
        lastAppliedSeq: nextSeq,
      );

    case CompactionEndedEvent():
      return current.copyWith(
        agentStatus: current.isStreaming
            ? AgentStatus.working
            : AgentStatus.settled,
        lastAppliedSeq: nextSeq,
      );

    case RetryStartedEvent():
      return current.copyWith(
        agentStatus: AgentStatus.retrying,
        lastAppliedSeq: nextSeq,
      );

    case UiRequestEvent(
      :final requestId,
      :final method,
      :final title,
      :final message,
      :final dialog,
    ):
      final nextRequests = List<Map<String, dynamic>>.from(
        current.pendingUiRequests,
      );
      nextRequests.add({
        'requestId': requestId,
        'method': method,
        'title': title,
        'message': message,
        'dialog': dialog,
        ...event.payload,
      });
      return current.copyWith(
        pendingUiRequests: nextRequests,
        agentStatus: dialog ? AgentStatus.awaitingUser : current.agentStatus,
        lastAppliedSeq: nextSeq,
      );

    case UiResolvedEvent(:final requestId):
      final nextRequests = current.pendingUiRequests
          .where((r) => r['requestId'] != requestId)
          .toList();
      return current.copyWith(
        pendingUiRequests: nextRequests,
        agentStatus: current.agentStatus == AgentStatus.awaitingUser
            ? (current.isStreaming ? AgentStatus.working : AgentStatus.settled)
            : current.agentStatus,
        lastAppliedSeq: nextSeq,
      );

    case WorkerCrashedEvent():
      return current.copyWith(
        agentStatus: AgentStatus.workerError,
        lastAppliedSeq: nextSeq,
      );

    case UnknownEvent():
      // Forward compatibility: ignore unknown events safely
      return current.copyWith(lastAppliedSeq: nextSeq);

    default:
      return current.copyWith(lastAppliedSeq: nextSeq);
  }
}

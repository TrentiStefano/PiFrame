import 'package:pi_crust_protocol/pi_crust_protocol.dart';
import 'agent_status.dart';
import 'session_state.dart';

SessionState reduceSessionState(SessionState current, PcpEvent event) {
  // Deduplicate on sequence number if assigned
  if (event.seq > 0 && event.seq <= current.lastAppliedSeq) {
    return current;
  }

  final nextSeq = event.seq > current.lastAppliedSeq ? event.seq : current.lastAppliedSeq;

  switch (event) {
    case RunStartedEvent():
      return current.copyWith(
        agentStatus: AgentStatus.working,
        lastAppliedSeq: nextSeq,
      );

    case RunEndedEvent(:final willRetry):
      return current.copyWith(
        agentStatus: willRetry ? AgentStatus.retrying : current.agentStatus,
        lastAppliedSeq: nextSeq,
      );

    case RunSettledEvent():
      return current.copyWith(
        agentStatus: AgentStatus.settled,
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
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
      final id = (msg['id'] as String?) ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
      
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

      final entry = SessionEntry(
        id: id,
        role: role,
        text: text,
        thinking: current.currentStreamingThinking.isNotEmpty ? current.currentStreamingThinking : null,
        toolCalls: current.activeToolCalls.values.toList(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final nextEntries = List<SessionEntry>.from(current.entries)..add(entry);
      return current.copyWith(
        entries: nextEntries,
        streamingTextBlocks: const {},
        streamingThinkingBlocks: const {},
        activeToolCalls: const {},
        lastAppliedSeq: nextSeq,
      );

    case ToolStartedEvent(:final toolCallId, :final toolName, :final args):
      final nextActive = Map<String, ToolExecutionState>.from(current.activeToolCalls);
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

    case ToolProgressEvent(:final toolCallId, :final toolName, :final partialResult):
      // Cumulative replacement rule: partialResult is NOT a delta
      final outputStr = partialResult?.toString() ?? '';
      final nextOutputs = Map<String, String>.from(current.toolOutputs);
      nextOutputs[toolCallId] = outputStr;

      final nextActive = Map<String, ToolExecutionState>.from(current.activeToolCalls);
      final existing = nextActive[toolCallId];
      if (existing != null) {
        nextActive[toolCallId] = existing.copyWith(
          output: outputStr,
        );
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

    case ToolCompletedEvent(:final toolCallId, :final toolName, :final result, :final isError, :final durationMs):
      final outputStr = result?.toString() ?? '';
      final nextOutputs = Map<String, String>.from(current.toolOutputs);
      nextOutputs[toolCallId] = outputStr;

      final nextActive = Map<String, ToolExecutionState>.from(current.activeToolCalls);
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

      return current.copyWith(
        activeToolCalls: nextActive,
        toolOutputs: nextOutputs,
        lastAppliedSeq: nextSeq,
      );

    case QueueChangedEvent(:final steering, :final followUp):
      return current.copyWith(
        steeringQueue: List<String>.from(steering),
        followUpQueue: List<String>.from(followUp),
        lastAppliedSeq: nextSeq,
      );

    case UsageUpdatedEvent(:final usage):
      return current.copyWith(
        usage: usage,
        lastAppliedSeq: nextSeq,
      );

    case CompactionStartedEvent():
      return current.copyWith(
        agentStatus: AgentStatus.compacting,
        lastAppliedSeq: nextSeq,
      );

    case CompactionEndedEvent():
      return current.copyWith(
        agentStatus: current.isStreaming ? AgentStatus.working : AgentStatus.settled,
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
        :final dialog
      ):
      final nextRequests = List<Map<String, dynamic>>.from(current.pendingUiRequests);
      nextRequests.add({
        'requestId': requestId,
        'method': method,
        'title': title,
        'message': message,
        'dialog': dialog,
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

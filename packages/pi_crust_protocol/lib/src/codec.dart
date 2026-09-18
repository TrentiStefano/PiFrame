import 'dart:convert';
import 'envelope.dart';
import 'commands.dart';
import 'events.dart';
import 'snapshot.dart';

/// Serialization and deserialization codec for PCP/1.
class PcpCodec {
  static PcpEnvelope decodeMessage(String raw) {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Message must be a JSON object: $raw');
    }
    return decodeMap(decoded);
  }

  static PcpEnvelope decodeMap(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? '';
    switch (kind) {
      case 'command':
        return PcpCommand.fromJson(json);
      case 'snapshot':
        return PcpSnapshot.fromJson(json);
      case 'event':
        return decodeEvent(json);
      default:
        return PcpEnvelope.fromJson(json);
    }
  }

  static PcpEvent decodeEvent(Map<String, dynamic> json) {
    final protocol = json['protocol'] as int? ?? 1;
    final id = json['id'] as String? ?? '';
    final ts = json['ts'] as int? ?? 0;
    final sessionId = json['sessionId'] as String? ?? '';
    final seq = json['seq'] as int? ?? 0;
    final type = json['type'] as String? ?? '';
    final payload = (json['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    switch (type) {
      case 'session.status':
        return SessionStatusEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'run.started':
        return RunStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'run.ended':
        return RunEndedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'run.settled':
        return RunSettledEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'turn.started':
        return TurnStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'turn.ended':
        return TurnEndedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'message.started':
        return MessageStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'message.completed':
        return MessageCompletedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'text.started':
        return TextStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'text.delta':
        return TextDeltaEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'text.completed':
        return TextCompletedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'thinking.started':
        return ThinkingStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'thinking.delta':
        return ThinkingDeltaEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'thinking.completed':
        return ThinkingCompletedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'toolcall.started':
        return ToolCallStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'toolcall.argsDelta':
        return ToolCallArgsDeltaEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'toolcall.completed':
        return ToolCallCompletedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'usage.updated':
        return UsageUpdatedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'tool.started':
        return ToolStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'tool.progress':
        return ToolProgressEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'tool.completed':
        return ToolCompletedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'queue.changed':
        return QueueChangedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'compaction.started':
        return CompactionStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'compaction.ended':
        return CompactionEndedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'retry.started':
        return RetryStartedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'retry.ended':
        return RetryEndedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'summarization.retry':
        return SummarizationRetryEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'bash.output':
        return BashOutputEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'extension.error':
        return ExtensionErrorEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.request':
        return UiRequestEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.claimed':
        return UiClaimedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.resolved':
        return UiResolvedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.notify':
        return UiNotifyEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.status':
        return UiStatusEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.widget':
        return UiWidgetEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.editorText':
        return UiEditorTextEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'ui.title':
        return UiTitleEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'workspace.changed':
        return WorkspaceChangedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'worker.diagnostic':
        return WorkerDiagnosticEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'worker.crashed':
        return WorkerCrashedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'journal.gap':
        return JournalGapEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'session.indexChanged':
        return SessionIndexChangedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      case 'daemon.configChanged':
        return DaemonConfigChangedEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, payload: payload);
      default:
        return UnknownEvent(protocol: protocol, id: id, ts: ts, sessionId: sessionId, seq: seq, type: type, payload: payload);
    }
  }

  static String encodeMessage(PcpEnvelope envelope) {
    return jsonEncode(envelope.toJson());
  }
}

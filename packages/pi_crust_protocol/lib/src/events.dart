import 'envelope.dart';

/// Base sealed class for all normalized PCP/1 events.
/// This enables exhaustive pattern matching in Dart 3 reducers.
sealed class PcpEvent extends PcpEnvelope {
  @override
  String get sessionId => super.sessionId!;

  @override
  int get seq => super.seq!;

  const PcpEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required String sessionId,
    required int seq,
    required super.type,
    required super.payload,
  }) : super(
          kind: 'event',
          sessionId: sessionId,
          seq: seq,
        );
}

// -----------------------------------------------------------------------------
// Lifecycle Events
// -----------------------------------------------------------------------------

class SessionStatusEvent extends PcpEvent {
  String get status => payload['status'] as String? ?? 'idle';
  String? get reason => payload['reason'] as String?;

  const SessionStatusEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'session.status');
}

class RunStartedEvent extends PcpEvent {
  const RunStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'run.started');
}

class RunEndedEvent extends PcpEvent {
  bool get willRetry => payload['willRetry'] as bool? ?? false;

  const RunEndedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'run.ended');
}

class RunSettledEvent extends PcpEvent {
  const RunSettledEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'run.settled');
}

class TurnStartedEvent extends PcpEvent {
  const TurnStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'turn.started');
}

class TurnEndedEvent extends PcpEvent {
  Map<String, dynamic>? get message => payload['message'] as Map<String, dynamic>?;
  List<dynamic> get toolResults => (payload['toolResults'] as List<dynamic>?) ?? const [];

  const TurnEndedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'turn.ended');
}

// -----------------------------------------------------------------------------
// Message Streaming Events
// -----------------------------------------------------------------------------

class MessageStartedEvent extends PcpEvent {
  Map<String, dynamic>? get message => payload['message'] as Map<String, dynamic>?;

  const MessageStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'message.started');
}

class MessageCompletedEvent extends PcpEvent {
  Map<String, dynamic>? get message => payload['message'] as Map<String, dynamic>?;

  const MessageCompletedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'message.completed');
}

class TextStartedEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;

  const TextStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'text.started');
}

class TextDeltaEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  String get delta => payload['delta'] as String? ?? '';

  const TextDeltaEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'text.delta');
}

class TextCompletedEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  String get content => payload['content'] as String? ?? '';

  const TextCompletedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'text.completed');
}

class ThinkingStartedEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;

  const ThinkingStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'thinking.started');
}

class ThinkingDeltaEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  String get delta => payload['delta'] as String? ?? '';

  const ThinkingDeltaEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'thinking.delta');
}

class ThinkingCompletedEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  String get content => payload['content'] as String? ?? '';

  const ThinkingCompletedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'thinking.completed');
}

class ToolCallStartedEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  String get toolCallId => payload['toolCallId'] as String? ?? '';
  String get toolName => payload['toolName'] as String? ?? '';

  const ToolCallStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'toolcall.started');
}

class ToolCallArgsDeltaEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  String get delta => payload['delta'] as String? ?? '';

  const ToolCallArgsDeltaEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'toolcall.argsDelta');
}

class ToolCallCompletedEvent extends PcpEvent {
  int get contentIndex => payload['contentIndex'] as int? ?? 0;
  Map<String, dynamic>? get toolCall => payload['toolCall'] as Map<String, dynamic>?;

  const ToolCallCompletedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'toolcall.completed');
}

class UsageUpdatedEvent extends PcpEvent {
  Map<String, dynamic> get usage => (payload['usage'] as Map<String, dynamic>?) ?? const {};

  const UsageUpdatedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'usage.updated');
}

// -----------------------------------------------------------------------------
// Tool Execution Events
// -----------------------------------------------------------------------------

class ToolStartedEvent extends PcpEvent {
  String get toolCallId => payload['toolCallId'] as String? ?? '';
  String get toolName => payload['toolName'] as String? ?? '';
  Map<String, dynamic> get args => (payload['args'] as Map<String, dynamic>?) ?? const {};

  const ToolStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'tool.started');
}

class ToolProgressEvent extends PcpEvent {
  String get toolCallId => payload['toolCallId'] as String? ?? '';
  String get toolName => payload['toolName'] as String? ?? '';
  dynamic get partialResult => payload['partialResult'];

  const ToolProgressEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'tool.progress');
}

class ToolCompletedEvent extends PcpEvent {
  String get toolCallId => payload['toolCallId'] as String? ?? '';
  String get toolName => payload['toolName'] as String? ?? '';
  dynamic get result => payload['result'];
  bool get isError => payload['isError'] as bool? ?? false;
  int? get durationMs => payload['durationMs'] as int?;

  const ToolCompletedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'tool.completed');
}

// -----------------------------------------------------------------------------
// Queue, Compaction, Retry Events
// -----------------------------------------------------------------------------

class QueueChangedEvent extends PcpEvent {
  List<String> get steering => (payload['steering'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
  List<String> get followUp => (payload['followUp'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];

  const QueueChangedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'queue.changed');
}

class CompactionStartedEvent extends PcpEvent {
  String get reason => payload['reason'] as String? ?? 'manual';

  const CompactionStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'compaction.started');
}

class CompactionEndedEvent extends PcpEvent {
  Map<String, dynamic>? get result => payload['result'] as Map<String, dynamic>?;
  bool get aborted => payload['aborted'] as bool? ?? false;
  bool get willRetry => payload['willRetry'] as bool? ?? false;

  const CompactionEndedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'compaction.ended');
}

class RetryStartedEvent extends PcpEvent {
  int get attempt => payload['attempt'] as int? ?? 1;
  int get maxAttempts => payload['maxAttempts'] as int? ?? 3;
  int get delayMs => payload['delayMs'] as int? ?? 0;
  String get errorMessage => payload['errorMessage'] as String? ?? '';

  const RetryStartedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'retry.started');
}

class RetryEndedEvent extends PcpEvent {
  bool get success => payload['success'] as bool? ?? false;
  int get attempt => payload['attempt'] as int? ?? 1;

  const RetryEndedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'retry.ended');
}

class SummarizationRetryEvent extends PcpEvent {
  String? get phase => payload['phase'] as String?;
  int? get attempt => payload['attempt'] as int?;

  const SummarizationRetryEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'summarization.retry');
}

class BashOutputEvent extends PcpEvent {
  @override
  String get commandId => payload['commandId'] as String? ?? '';
  String get output => payload['output'] as String? ?? '';

  const BashOutputEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'bash.output');
}

class ExtensionErrorEvent extends PcpEvent {
  String? get extensionPath => payload['extensionPath'] as String?;
  String? get eventName => payload['event'] as String?;
  dynamic get error => payload['error'];

  const ExtensionErrorEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'extension.error');
}

// -----------------------------------------------------------------------------
// Extension UI Events
// -----------------------------------------------------------------------------

class UiRequestEvent extends PcpEvent {
  String get requestId => payload['requestId'] as String? ?? '';
  String get method => payload['method'] as String? ?? '';
  String? get title => payload['title'] as String?;
  String? get message => payload['message'] as String?;
  List<String> get options => (payload['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
  String? get placeholder => payload['placeholder'] as String?;
  String? get prefill => payload['prefill'] as String?;
  int? get timeoutMs => payload['timeoutMs'] as int?;
  bool get dialog => payload['dialog'] as bool? ?? true;
  String? get claimedBy => payload['claimedBy'] as String?;

  const UiRequestEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.request');
}

class UiClaimedEvent extends PcpEvent {
  String get requestId => payload['requestId'] as String? ?? '';
  String get clientId => payload['clientId'] as String? ?? '';

  const UiClaimedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.claimed');
}

class UiResolvedEvent extends PcpEvent {
  String get requestId => payload['requestId'] as String? ?? '';
  String get resolution => payload['resolution'] as String? ?? '';
  String? get byClientId => payload['byClientId'] as String?;

  const UiResolvedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.resolved');
}

class UiNotifyEvent extends PcpEvent {
  String get level => payload['level'] as String? ?? 'info';
  String get message => payload['message'] as String? ?? '';

  const UiNotifyEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.notify');
}

class UiStatusEvent extends PcpEvent {
  String get statusKey => payload['statusKey'] as String? ?? '';
  String? get statusText => payload['statusText'] as String?;

  const UiStatusEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.status');
}

class UiWidgetEvent extends PcpEvent {
  String get widgetKey => payload['widgetKey'] as String? ?? '';
  List<String> get lines => (payload['lines'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
  String? get placement => payload['placement'] as String?;

  const UiWidgetEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.widget');
}

class UiEditorTextEvent extends PcpEvent {
  String get text => payload['text'] as String? ?? '';

  const UiEditorTextEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.editorText');
}

class UiTitleEvent extends PcpEvent {
  String get title => payload['title'] as String? ?? '';

  const UiTitleEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'ui.title');
}

// -----------------------------------------------------------------------------
// Workspace & Daemon Events
// -----------------------------------------------------------------------------

class WorkspaceChangedEvent extends PcpEvent {
  List<dynamic> get changedFiles => (payload['changedFiles'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get diffStat => (payload['diffStat'] as Map<String, dynamic>?) ?? const {};
  String? get branch => payload['branch'] as String?;
  bool get dirty => payload['dirty'] as bool? ?? false;

  const WorkspaceChangedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'workspace.changed');
}

class WorkerDiagnosticEvent extends PcpEvent {
  String get level => payload['level'] as String? ?? 'info';
  String get message => payload['message'] as String? ?? '';
  String get source => payload['source'] as String? ?? 'supervisor';

  const WorkerDiagnosticEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'worker.diagnostic');
}

class WorkerCrashedEvent extends PcpEvent {
  int? get exitCode => payload['exitCode'] as int?;
  String? get signal => payload['signal'] as String?;
  String get lastStderr => payload['lastStderr'] as String? ?? '';
  bool get recoverable => payload['recoverable'] as bool? ?? false;

  const WorkerCrashedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'worker.crashed');
}

class JournalGapEvent extends PcpEvent {
  int get fromSeq => payload['fromSeq'] as int? ?? 0;
  int get toSeq => payload['toSeq'] as int? ?? 0;

  const JournalGapEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'journal.gap');
}

class SessionIndexChangedEvent extends PcpEvent {
  List<dynamic> get added => (payload['added'] as List<dynamic>?) ?? const [];
  List<dynamic> get updated => (payload['updated'] as List<dynamic>?) ?? const [];
  List<dynamic> get removed => (payload['removed'] as List<dynamic>?) ?? const [];

  const SessionIndexChangedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'session.indexChanged');
}

class DaemonConfigChangedEvent extends PcpEvent {
  Map<String, dynamic> get config => (payload['config'] as Map<String, dynamic>?) ?? const {};

  const DaemonConfigChangedEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.payload,
  }) : super(type: 'daemon.configChanged');
}

// -----------------------------------------------------------------------------
// Forward Compatibility: UnknownEvent
// -----------------------------------------------------------------------------

/// Catches any future/unrecognized event types without breaking deserialization.
class UnknownEvent extends PcpEvent {
  const UnknownEvent({
    required super.protocol,
    required super.id,
    required super.ts,
    required super.sessionId,
    required super.seq,
    required super.type,
    required super.payload,
  });
}

import 'envelope.dart';

/// Full authoritative snapshot of a session.
class PcpSnapshot extends PcpEnvelope {
  @override
  String get sessionId => super.sessionId!;

  @override
  int get seq => super.seq!;

  SessionMeta get session => SessionMeta.fromJson((payload['session'] as Map<String, dynamic>?) ?? {});
  RuntimeMeta get runtime => RuntimeMeta.fromJson((payload['runtime'] as Map<String, dynamic>?) ?? {});
  TranscriptMeta get transcript => TranscriptMeta.fromJson((payload['transcript'] as Map<String, dynamic>?) ?? {});
  Map<String, dynamic>? get liveMessage => payload['liveMessage'] as Map<String, dynamic>?;
  List<dynamic> get activeTools => (payload['activeTools'] as List<dynamic>?) ?? const [];
  List<dynamic> get pendingUiRequests => (payload['pendingUiRequests'] as List<dynamic>?) ?? const [];
  Map<String, dynamic> get usage => (payload['usage'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get workspace => (payload['workspace'] as Map<String, dynamic>?) ?? const {};

  const PcpSnapshot({
    required super.protocol,
    required super.id,
    required super.ts,
    required String sessionId,
    required int seq,
    required super.payload,
  }) : super(
          kind: 'snapshot',
          sessionId: sessionId,
          seq: seq,
          type: 'session.snapshot',
        );

  factory PcpSnapshot.fromJson(Map<String, dynamic> json) {
    return PcpSnapshot(
      protocol: json['protocol'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      ts: json['ts'] as int? ?? 0,
      sessionId: json['sessionId'] as String? ?? '',
      seq: json['seq'] as int? ?? 0,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }
}

class SessionMeta {
  final String id;
  final String? name;
  final String cwd;
  final String? gitRoot;
  final String? sessionFile;
  final int? createdAt;
  final int? lastActivityAt;

  const SessionMeta({
    required this.id,
    this.name,
    required this.cwd,
    this.gitRoot,
    this.sessionFile,
    this.createdAt,
    this.lastActivityAt,
  });

  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    return SessionMeta(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      cwd: json['cwd'] as String? ?? '',
      gitRoot: json['gitRoot'] as String?,
      sessionFile: json['sessionFile'] as String?,
      createdAt: json['createdAt'] as int?,
      lastActivityAt: json['lastActivityAt'] as int?,
    );
  }
}

class RuntimeMeta {
  final String status;
  final Map<String, dynamic>? model;
  final String? thinkingLevel;
  final String? steeringMode;
  final String? followUpMode;
  final bool isStreaming;
  final bool isCompacting;
  final bool autoCompaction;
  final List<String> steeringQueue;
  final List<String> followUpQueue;

  const RuntimeMeta({
    required this.status,
    this.model,
    this.thinkingLevel,
    this.steeringMode,
    this.followUpMode,
    required this.isStreaming,
    required this.isCompacting,
    required this.autoCompaction,
    required this.steeringQueue,
    required this.followUpQueue,
  });

  factory RuntimeMeta.fromJson(Map<String, dynamic> json) {
    final queue = json['queue'] as Map<String, dynamic>? ?? {};
    return RuntimeMeta(
      status: json['status'] as String? ?? 'idle',
      model: json['model'] as Map<String, dynamic>?,
      thinkingLevel: json['thinkingLevel'] as String?,
      steeringMode: json['steeringMode'] as String?,
      followUpMode: json['followUpMode'] as String?,
      isStreaming: json['isStreaming'] as bool? ?? false,
      isCompacting: json['isCompacting'] as bool? ?? false,
      autoCompaction: json['autoCompaction'] as bool? ?? true,
      steeringQueue: (queue['steering'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      followUpQueue: (queue['followUp'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

class TranscriptMeta {
  final List<dynamic> entries;
  final String? leafId;

  const TranscriptMeta({
    required this.entries,
    this.leafId,
  });

  factory TranscriptMeta.fromJson(Map<String, dynamic> json) {
    return TranscriptMeta(
      entries: (json['entries'] as List<dynamic>?) ?? const [],
      leafId: json['leafId'] as String?,
    );
  }
}

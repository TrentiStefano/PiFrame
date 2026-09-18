/// PCP/1 Protocol Envelope definitions.
class PcpEnvelope {
  final int protocol;
  final String kind;
  final String id;
  final int ts;
  final String? commandId;
  final String? sessionId;
  final int? seq;
  final String type;
  final Map<String, dynamic> payload;

  const PcpEnvelope({
    required this.protocol,
    required this.kind,
    required this.id,
    required this.ts,
    this.commandId,
    this.sessionId,
    this.seq,
    required this.type,
    required this.payload,
  });

  factory PcpEnvelope.fromJson(Map<String, dynamic> json) {
    return PcpEnvelope(
      protocol: json['protocol'] as int? ?? 1,
      kind: json['kind'] as String? ?? '',
      id: json['id'] as String? ?? '',
      ts: json['ts'] as int? ?? 0,
      commandId: json['commandId'] as String?,
      sessionId: json['sessionId'] as String?,
      seq: json['seq'] as int?,
      type: json['type'] as String? ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'kind': kind,
      'id': id,
      'ts': ts,
      if (commandId != null) 'commandId': commandId,
      if (sessionId != null) 'sessionId': sessionId,
      if (seq != null) 'seq': seq,
      'type': type,
      'payload': payload,
    };
  }

  @override
  String toString() => 'PcpEnvelope($kind, $type, id=$id, seq=$seq)';
}

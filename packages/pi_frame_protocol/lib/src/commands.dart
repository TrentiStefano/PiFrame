import 'envelope.dart';

/// Client command message in PCP/1.
class PcpCommand extends PcpEnvelope {
  @override
  String get commandId => super.commandId!;

  const PcpCommand({
    required super.protocol,
    required super.id,
    required super.ts,
    required String commandId,
    super.sessionId,
    required super.type,
    required super.payload,
  }) : super(
          kind: 'command',
          commandId: commandId,
        );

  factory PcpCommand.create({
    required String commandId,
    String? sessionId,
    required String type,
    Map<String, dynamic> payload = const {},
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return PcpCommand(
      protocol: 1,
      id: 'cmd_msg_$now',
      ts: now,
      commandId: commandId,
      sessionId: sessionId,
      type: type,
      payload: payload,
    );
  }

  factory PcpCommand.fromJson(Map<String, dynamic> json) {
    return PcpCommand(
      protocol: json['protocol'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      ts: json['ts'] as int? ?? 0,
      commandId: json['commandId'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      type: json['type'] as String? ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }
}

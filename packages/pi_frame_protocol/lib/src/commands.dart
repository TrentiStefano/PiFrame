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

  static PcpCommand systemMetricsSubscribe({required String commandId}) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: '@daemon',
      type: 'system.metrics.subscribe',
      payload: const {},
    );
  }

  static PcpCommand systemMetricsUnsubscribe({required String commandId}) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: '@daemon',
      type: 'system.metrics.unsubscribe',
      payload: const {},
    );
  }

  static PcpCommand workspaceListBranches({
    required String commandId,
    required String sessionId,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: sessionId,
      type: 'workspace.listBranches',
      payload: const {},
    );
  }

  static PcpCommand workspaceSwitchBranch({
    required String commandId,
    required String sessionId,
    required String branch,
    String onDirty = 'block',
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: sessionId,
      type: 'workspace.switchBranch',
      payload: {
        'branch': branch,
        'onDirty': onDirty,
      },
    );
  }

  static PcpCommand piAgentsGet({
    required String commandId,
    String? cwd,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: '@daemon',
      type: 'pi.agents.get',
      payload: cwd != null ? {'cwd': cwd} : const {},
    );
  }

  static PcpCommand piAgentsUpdate({
    required String commandId,
    required List<Map<String, dynamic>> changes,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: '@daemon',
      type: 'pi.agents.update',
      payload: {'changes': changes},
    );
  }

  static PcpCommand sideOpen({
    required String commandId,
    required String sessionId,
    String? question,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: sessionId,
      type: 'side.open',
      payload: {
        'sessionId': sessionId,
        if (question != null) 'question': question,
      },
    );
  }

  static PcpCommand sidePrompt({
    required String commandId,
    required String sideId,
    required String text,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: sideId,
      type: 'side.prompt',
      payload: {
        'sideId': sideId,
        'text': text,
      },
    );
  }

  static PcpCommand sideAbort({
    required String commandId,
    required String sideId,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: sideId,
      type: 'side.abort',
      payload: {
        'sideId': sideId,
      },
    );
  }

  static PcpCommand sideClose({
    required String commandId,
    required String sideId,
  }) {
    return PcpCommand.create(
      commandId: commandId,
      sessionId: sideId,
      type: 'side.close',
      payload: {
        'sideId': sideId,
      },
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

import '../../app/app_version.dart';
import '../agents/agents_config_model.dart';

enum DaemonConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
}

class PcpClient {
  final String host;
  int port;
  String token;
  final Future<({int port, String token})?> Function()? rediscover;

  static int _commandCounter = 0;
  static String newCommandId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_commandCounter++}';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  DaemonConnectionState _state = DaemonConnectionState.disconnected;

  final _connectionStateController =
      StreamController<DaemonConnectionState>.broadcast();
  Stream<DaemonConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  DaemonConnectionState get state => _state;

  // Session event streams
  final _eventControllers = <String, StreamController<PcpEvent>>{};
  final _snapshotControllers = <String, StreamController<PcpSnapshot>>{};

  // Correlated pending commands: commandId -> Completer
  final _pendingCommands = <String, Completer<Map<String, dynamic>>>{};
  final _inFlightCommands = <String, PcpCommand>{};

  // Reconnect management
  bool _disposed = false;
  int _reconnectDelaySeconds = 1;
  Timer? _reconnectTimer;

  final bool isSecure;

  // Attached sessions with lastSeq
  final _attachedSessions = <String, int?>{};

  Map<String, dynamic>? _welcomePayload;
  Map<String, dynamic>? get welcomePayload => _welcomePayload;

  List<String>? _customCapabilities;
  @visibleForTesting
  set customCapabilities(List<String>? caps) => _customCapabilities = caps;

  List<String> get capabilities {
    if (_customCapabilities != null) return _customCapabilities!;
    final caps = _welcomePayload?['capabilities'];
    if (caps is List) {
      return caps.map((e) => e.toString()).toList();
    }
    return const [];
  }

  bool hasCapability(String capability) => capabilities.contains(capability);

  PcpClient({
    this.host = '127.0.0.1',
    required this.port,
    required this.token,
    this.isSecure = false,
    this.rediscover,
  });

  void connect() {
    if (_disposed) return;
    _setConnectionState(DaemonConnectionState.connecting);

    try {
      final scheme = isSecure ? 'wss' : 'ws';
      final portSuffix = (isSecure && port == 443) || (!isSecure && port == 80)
          ? ''
          : ':$port';
      final uri = Uri.parse('$scheme://$host$portSuffix');
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _sendHello();
    } catch (e) {
      _onError(e);
    }
  }

  void _sendHello() {
    _setConnectionState(DaemonConnectionState.authenticating);
    final hello = {
      'protocol': 1,
      'kind': 'hello',
      'id': 'hl_${DateTime.now().millisecondsSinceEpoch}',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'type': 'connection.hello',
      'payload': {
        'token': token,
        'client': {
          'name': 'pi_frame_flutter',
          'version': piFrameVersion,
          'platform': defaultTargetPlatform.name,
        },
        'encoding': 'json',
        'capabilities': ['replay.v1', 'ui.claim.v1', 'workspace.v1'],
      },
    };
    _sendRaw(jsonEncode(hello));
  }

  void _onMessage(dynamic raw) {
    try {
      final String text = raw is String
          ? raw
          : (raw is List<int> ? utf8.decode(raw) : raw.toString());
      final map = jsonDecode(text) as Map<String, dynamic>;
      final kind = map['kind'] as String?;

      if (kind == 'welcome') {
        _welcomePayload = map['payload'] as Map<String, dynamic>?;
        _setConnectionState(DaemonConnectionState.connected);
        _reconnectDelaySeconds = 1;

        // Re-attach all active sessions
        for (final entry in _attachedSessions.entries) {
          attach(entry.key, lastSeq: entry.value);
        }

        // Re-send in-flight commands with identical commandId (excluding attaches)
        for (final cmd in _inFlightCommands.values) {
          if (cmd.type != 'session.attach') {
            _sendRaw(PcpCodec.encodeMessage(cmd));
          }
        }
        return;
      }

      if (kind == 'ping') {
        final pong = {
          'protocol': 1,
          'kind': 'pong',
          'id': 'png_${DateTime.now().millisecondsSinceEpoch}',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'type': 'heartbeat.pong',
          'payload': {},
        };
        _sendRaw(jsonEncode(pong));
        return;
      }

      if (kind == 'ack') {
        // Ack received
        return;
      }

      if (kind == 'result') {
        final commandId = map['commandId'] as String?;
        if (commandId != null && _pendingCommands.containsKey(commandId)) {
          final completer = _pendingCommands.remove(commandId)!;
          _inFlightCommands.remove(commandId);
          final payload = map['payload'] as Map<String, dynamic>? ?? {};
          if (payload['state'] == 'failed' || payload['state'] == 'rejected') {
            final code = payload['code']?.toString() ?? '';
            final details = payload['details'];
            completer.completeError(
              PcpException(
                payload['error']?.toString() ?? 'Command failed',
                code: code,
                details: details ?? const {},
              ),
            );
          } else {
            completer.complete(payload);
          }
        }
        return;
      }

      if (kind == 'error') {
        final commandId = map['commandId'] as String?;
        if (commandId != null && _pendingCommands.containsKey(commandId)) {
          final completer = _pendingCommands.remove(commandId)!;
          _inFlightCommands.remove(commandId);
          final payload = map['payload'] as Map<String, dynamic>? ?? {};
          completer.completeError(
            PcpException(
              payload['message']?.toString() ?? 'PCP Error',
              code: payload['code']?.toString() ?? '',
              details: payload['details'] ?? const {},
            ),
          );
        }
        return;
      }

      if (kind == 'snapshot') {
        final snapshot = PcpSnapshot.fromJson(map);
        final sessionId = snapshot.sessionId;
        _attachedSessions[sessionId] = snapshot.seq;
        if (_snapshotControllers.containsKey(sessionId)) {
          _snapshotControllers[sessionId]!.add(snapshot);
        }
        return;
      }

      if (kind == 'event') {
        final event = PcpCodec.decodeEvent(map);
        final sessionId = event.sessionId;
        if (sessionId != '@daemon') {
          final lastSeq = _attachedSessions[sessionId];
          if (event.seq > 0) {
            if (event.type != 'journal.gap' &&
                lastSeq != null &&
                event.seq <= lastSeq) {
              return;
            }
            _attachedSessions[sessionId] = event.seq;
          }
        }
        if (event.type == 'journal.gap') {
          // Re-sync by attaching without lastSeq to obtain a fresh full snapshot
          attach(sessionId, lastSeq: null);
        }
        if (_eventControllers.containsKey(sessionId)) {
          _eventControllers[sessionId]!.add(event);
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) print('Error parsing PCP frame: $e');
    }
  }

  void _onError(dynamic err) {
    if (kDebugMode) {
      debugPrint(
        'PCP WebSocket error: $err, closeCode=${_channel?.closeCode}, closeReason=${_channel?.closeReason}',
      );
    }
    _cleanupChannel();
    _scheduleReconnect();
  }

  void _onDone() {
    if (kDebugMode) {
      debugPrint(
        'PCP WebSocket closed. closeCode=${_channel?.closeCode}, closeReason=${_channel?.closeReason}',
      );
    }
    _cleanupChannel();
    _scheduleReconnect();
  }

  void _cleanupChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _welcomePayload = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setConnectionState(DaemonConnectionState.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: _reconnectDelaySeconds),
      () async {
        _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 15);
        try {
          final endpoint = await rediscover?.call();
          if (_disposed) return;
          if (endpoint != null &&
              (endpoint.port != port || endpoint.token != token)) {
            // A new daemon cannot deduplicate uncertain commands from the old daemon.
            for (final pending in _pendingCommands.values) {
              pending.completeError(
                StateError(
                  'Daemon restarted. Check session state before retrying the command.',
                ),
              );
            }
            _pendingCommands.clear();
            _inFlightCommands.clear();
            port = endpoint.port;
            token = endpoint.token;
          }
        } catch (_) {
          /* A later reconnect will retry discovery. */
        }
        if (!_disposed) connect();
      },
    );
  }

  void _setConnectionState(DaemonConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _connectionStateController.add(newState);
    }
  }

  void _sendRaw(String text) {
    try {
      _channel?.sink.add(text);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> sendCommand(PcpCommand command) {
    if (_disposed) return Future.error(StateError('PCP client is disposed'));
    final pending = _pendingCommands[command.commandId];
    if (pending != null) return pending.future;
    final completer = Completer<Map<String, dynamic>>();
    _pendingCommands[command.commandId] = completer;
    _inFlightCommands[command.commandId] = command;

    if (_state == DaemonConnectionState.connected) {
      _sendRaw(PcpCodec.encodeMessage(command));
    }
    return completer.future;
  }

  void attach(String sessionId, {int? lastSeq}) {
    _attachedSessions[sessionId] = lastSeq;
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('att'),
      type: 'session.attach',
      payload: {'lastSeq': lastSeq},
    );
    unawaited(
      sendCommand(cmd).catchError((Object error) {
        if (kDebugMode) debugPrint('Session attach failed: $error');
        return <String, dynamic>{};
      }),
    );
  }

  Future<Map<String, dynamic>> getHistory(
    String sessionId, {
    String? beforeId,
    int limit = 50,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('gh'),
      type: 'session.getHistory',
      payload: {'sessionId': sessionId, 'beforeId': ?beforeId, 'limit': limit},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> sendPrompt(
    String sessionId,
    String text, {
    String? streamingBehavior,
    List<dynamic>? images,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('prm'),
      type: 'agent.prompt',
      payload: {
        'text': text,
        'streamingBehavior': ?streamingBehavior,
        'images': ?images,
      },
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> interruptAgent(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('int'),
      type: 'agent.interrupt',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> clearQueue(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('cq'),
      type: 'agent.clearQueue',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> compactContext(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('cmp'),
      type: 'agent.compact',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setContextWindowOverride(
    String sessionId,
    int? limit,
  ) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('scw'),
      type: 'agent.setContextWindowOverride',
      payload: {'limit': limit},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setCompactionReservePercent(
    String sessionId,
    double percent,
  ) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('scr'),
      type: 'agent.setCompactionReservePercent',
      payload: {'percent': percent},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setModel(
    String sessionId,
    String provider,
    String modelId,
  ) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('sm'),
      type: 'agent.setModel',
      payload: {'provider': provider, 'modelId': modelId},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setThinkingLevel(
    String sessionId,
    String level,
  ) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('stl'),
      type: 'agent.setThinkingLevel',
      payload: {'level': level},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> piAuthLogin(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('pal'),
      type: 'agent.authLogin',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> piAuthLogout(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('pao'),
      type: 'agent.authLogout',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> getCommands(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('gc'),
      type: 'agent.getCommands',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> getAvailableModels(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('gm'),
      type: 'agent.getModels',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> getAvailableThinkingLevels(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('gtl'),
      type: 'agent.getThinkingLevels',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> getSessionStats(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('gss'),
      type: 'session.getStats',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> listPiPackages() => sendCommand(
    PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      commandId: newCommandId('pkgl'),
      type: 'pi.packages.list',
      payload: const {},
    ),
  );

  Future<Map<String, dynamic>> updatePiPackage(String source) => sendCommand(
    PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      commandId: newCommandId('pkgu'),
      type: 'pi.packages.update',
      payload: {'source': source},
    ),
  );

  Future<Map<String, dynamic>> removePiPackage(String source) => sendCommand(
    PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      commandId: newCommandId('pkgr'),
      type: 'pi.packages.remove',
      payload: {'source': source},
    ),
  );

  Future<Map<String, dynamic>> pinPiPackage(String source, String version) =>
      sendCommand(
        PcpCommand(
          protocol: 1,
          id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
          ts: DateTime.now().millisecondsSinceEpoch,
          commandId: newCommandId('pkgp'),
          type: 'pi.packages.pin',
          payload: {'source': source, 'version': version},
        ),
      );

  Future<PiAgentsConfig> getAgentsConfig({String? cwd}) async {
    final cmd = PcpCommand.piAgentsGet(
      commandId: newCommandId('ag_get'),
      cwd: cwd,
    );
    final res = await sendCommand(cmd);
    final map = (res['data'] as Map<String, dynamic>?) ?? res;
    return PiAgentsConfig.fromJson(map);
  }

  Future<PiAgentsConfig> updateAgentsConfig(List<Map> changes) async {
    final typedChanges = changes
        .map((c) => c.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    final cmd = PcpCommand.piAgentsUpdate(
      commandId: newCommandId('ag_upd'),
      changes: typedChanges,
    );
    final res = await sendCommand(cmd);
    final map = (res['data'] as Map<String, dynamic>?) ?? res;
    return PiAgentsConfig.fromJson(map);
  }

  Future<Map<String, dynamic>> claimUiRequest(
    String sessionId,
    String requestId,
  ) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('clr'),
      type: 'ui.claim',
      payload: {'requestId': requestId},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> respondUiRequest(
    String sessionId,
    String requestId, {
    dynamic value,
    bool? confirmed,
    bool? cancelled,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('rsr'),
      type: 'ui.respond',
      payload: {
        'requestId': requestId,
        'value': ?value,
        'confirmed': ?confirmed,
        'cancelled': ?cancelled,
      },
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> recoverSession(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('rcs'),
      type: 'session.open',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> continueSession(
    String sessionId, {
    bool confirmed = false,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('continue'),
      type: 'session.open',
      payload: {'continue': true, 'confirmed': confirmed},
    );
    return sendCommand(cmd);
  }

  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) async {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('sub'),
      type: 'session.subagents',
      payload: {},
    );
    final res = await sendCommand(cmd);
    final data = res['data'] as Map<String, dynamic>? ?? res;
    final list = data['subagents'];
    if (list is! List) {
      throw const FormatException('Missing subagents in daemon response');
    }
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> steerSubagent(
    String sessionId,
    String subagentId,
    String message,
  ) {
    return sendPrompt(
      sessionId,
      'Steer subagent $subagentId: $message',
      streamingBehavior: 'steer',
    );
  }

  Future<Map<String, dynamic>> stopSubagent(
    String sessionId,
    String subagentId,
  ) {
    return sendPrompt(
      sessionId,
      'Stop subagent $subagentId immediately.',
      streamingBehavior: 'steer',
    );
  }

  Future<Map<String, dynamic>> getDaemonConfig() {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('gdc'),
      type: 'daemon.getConfig',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setDaemonConfig(Map<String, dynamic> config) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('sdc'),
      type: 'daemon.setConfig',
      payload: config,
    );
    return sendCommand(cmd);
  }

  // ---------------------------------------------------------------------------
  // Remote Connection Management
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getRemoteStatus() {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_stat'),
      type: 'remote.getStatus',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> startRemoteTunnel({
    String? tunnelProvider,
    String? customCommand,
    String? customUrl,
  }) {
    final payload = <String, dynamic>{};
    if (tunnelProvider != null) payload['tunnelProvider'] = tunnelProvider;
    if (customCommand != null) payload['customCommand'] = customCommand;
    if (customUrl != null) payload['customUrl'] = customUrl;

    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_start'),
      type: 'remote.start',
      payload: payload,
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> installCloudflared() {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_inst_cf'),
      type: 'remote.installCloudflared',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> installTailscale() {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_inst_ts'),
      type: 'remote.installTailscale',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setTailscaleHostname(String hostname) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_set_ts_host'),
      type: 'remote.setTailscaleHostname',
      payload: {'hostname': hostname},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> stopRemoteTunnel() {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_stop'),
      type: 'remote.stop',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> generateRemotePairing({int? ttlMs}) {
    final payload = <String, dynamic>{};
    if (ttlMs != null) payload['ttlMs'] = ttlMs;

    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_pair'),
      type: 'remote.generatePairing',
      payload: payload,
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> revokeRemoteDevice(String deviceId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_rev'),
      type: 'remote.revokeDevice',
      payload: {'deviceId': deviceId},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> revokeAllRemoteDevices() {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_rev_all'),
      type: 'remote.revokeAll',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setRemoteDeviceMode({
    required String deviceId,
    required String mode,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_dev_mode'),
      type: 'remote.setDeviceMode',
      payload: {'deviceId': deviceId, 'mode': mode},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> setRemoteOptions({String? defaultMode}) {
    final payload = <String, dynamic>{};
    if (defaultMode != null) payload['defaultMode'] = defaultMode;

    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('rem_opt'),
      type: 'remote.setOptions',
      payload: payload,
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) =>
      _workspaceCommand(sessionId, 'workspace.listFiles', {});

  Future<Map<String, dynamic>> readWorkspaceFile(
    String sessionId,
    String path,
  ) => _workspaceCommand(sessionId, 'workspace.readFile', {'path': path});

  Future<Map<String, dynamic>> saveWorkspaceFile(
    String sessionId,
    Map<String, dynamic> payload,
  ) => _workspaceCommand(sessionId, 'workspace.saveFile', payload);

  Future<Map<String, dynamic>> workspaceGitAction(
    String sessionId,
    Map<String, dynamic> payload,
  ) => _workspaceCommand(sessionId, 'workspace.gitAction', payload);

  Future<Map<String, dynamic>> _workspaceCommand(
    String sessionId,
    String type,
    Map<String, dynamic> payload,
  ) {
    final command = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('ws'),
      type: type,
      payload: payload,
    );
    return sendCommand(command);
  }

  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('wkr'),
      type: 'workspace.refresh',
      payload: {'cwd': ?cwd},
    );
    return sendCommand(cmd);
  }

  Future<WorkspaceListBranchesResult> listBranches(String sessionId) async {
    final cmd = PcpCommand.workspaceListBranches(
      commandId: newCommandId('wlb'),
      sessionId: sessionId,
    );
    final response = await sendCommand(cmd);
    final data = (response['data'] as Map<String, dynamic>?) ?? response;
    return WorkspaceListBranchesResult.fromJson(data);
  }

  Future<WorkspaceSwitchBranchResult> switchBranch(
    String sessionId,
    String branch, {
    String onDirty = 'block',
  }) async {
    final cmd = PcpCommand.workspaceSwitchBranch(
      commandId: newCommandId('wsb'),
      sessionId: sessionId,
      branch: branch,
      onDirty: onDirty,
    );
    final response = await sendCommand(cmd);
    final data = (response['data'] as Map<String, dynamic>?) ?? response;
    return WorkspaceSwitchBranchResult.fromJson(data);
  }

  Future<Map<String, dynamic>> getWorkspaceDiff(
    String sessionId, {
    String? filePath,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('wkd'),
      type: 'workspace.getDiff',
      payload: {'filePath': ?filePath},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> listSessions({String? query, int? limit}) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: '@daemon',
      commandId: newCommandId('lss'),
      type: 'session.list',
      payload: {'query': ?query, 'limit': ?limit},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> renameSession(String sessionId, String name) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('rns'),
      type: 'session.rename',
      payload: {'name': name},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> deleteSession(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('del'),
      type: 'session.delete',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> forkSession(
    String sessionId, {
    String? entryId,
  }) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('frk'),
      type: 'session.fork',
      payload: {'entryId': ?entryId},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> cloneSession(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('cln'),
      type: 'session.clone',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> getSessionTree(String sessionId) {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: newCommandId('gtr'),
      type: 'session.getTree',
      payload: {},
    );
    return sendCommand(cmd);
  }

  Future<Map<String, dynamic>> subscribeSystemMetrics() {
    return sendCommand(
      PcpCommand.systemMetricsSubscribe(
        commandId: newCommandId('cmd_metrics_sub'),
      ),
    );
  }

  Future<Map<String, dynamic>> unsubscribeSystemMetrics() {
    return sendCommand(
      PcpCommand.systemMetricsUnsubscribe(
        commandId: newCommandId('cmd_metrics_unsub'),
      ),
    );
  }

  Stream<PcpEvent> events(String sessionId) {
    return _eventControllers
        .putIfAbsent(sessionId, () => StreamController<PcpEvent>.broadcast())
        .stream;
  }

  Stream<PcpSnapshot> snapshots(String sessionId) {
    return _snapshotControllers
        .putIfAbsent(sessionId, () => StreamController<PcpSnapshot>.broadcast())
        .stream;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanupChannel();
    for (final pending in _pendingCommands.values) {
      pending.completeError(StateError('PCP client is disposed'));
    }
    _pendingCommands.clear();
    _inFlightCommands.clear();
    _connectionStateController.close();
    for (final c in _eventControllers.values) {
      c.close();
    }
    for (final c in _snapshotControllers.values) {
      c.close();
    }
  }
}

class PcpException extends StateError implements Exception {
  final String code;
  final dynamic details;

  PcpException(
    super.message, {
    this.code = '',
    this.details = const {},
  });

  Map<String, dynamic> get detailsMap =>
      details is Map<String, dynamic>
          ? details as Map<String, dynamic>
          : (details is Map
              ? Map<String, dynamic>.from(details as Map)
              : const {});

  List<Map<String, dynamic>> get validationErrors {
    if (details is List) {
      return (details as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return const [];
  }

  int get changedFiles => (detailsMap['changedFiles'] as num?)?.toInt() ?? 0;
  int get untrackedFiles => (detailsMap['untrackedFiles'] as num?)?.toInt() ?? 0;
  String? get stderr => detailsMap['stderr']?.toString();
  bool get stashRetained => detailsMap['stashRetained'] == true;
  String? get stashMessage => detailsMap['stashMessage']?.toString();

  @override
  String toString() => 'Bad state: $message';
}

class WorkspaceBranchInfo {
  final String name;
  final bool isCurrent;
  final String? upstream;
  final int? ahead;
  final int? behind;
  final int? lastCommitUnix;

  const WorkspaceBranchInfo({
    required this.name,
    required this.isCurrent,
    this.upstream,
    this.ahead,
    this.behind,
    this.lastCommitUnix,
  });

  factory WorkspaceBranchInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceBranchInfo(
      name: json['name'] as String? ?? '',
      isCurrent: json['isCurrent'] as bool? ?? false,
      upstream: json['upstream'] as String?,
      ahead: (json['ahead'] as num?)?.toInt(),
      behind: (json['behind'] as num?)?.toInt(),
      lastCommitUnix: (json['lastCommitUnix'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'isCurrent': isCurrent,
    if (upstream != null) 'upstream': upstream,
    if (ahead != null) 'ahead': ahead,
    if (behind != null) 'behind': behind,
    if (lastCommitUnix != null) 'lastCommitUnix': lastCommitUnix,
  };
}

class WorkspaceListBranchesResult {
  final List<WorkspaceBranchInfo> branches;
  final String? currentBranch;
  final bool detached;
  final String? headShortSha;

  const WorkspaceListBranchesResult({
    required this.branches,
    this.currentBranch,
    this.detached = false,
    this.headShortSha,
  });

  factory WorkspaceListBranchesResult.fromJson(Map<String, dynamic> json) {
    final rawBranches = (json['branches'] as List?) ?? const [];
    final branches = rawBranches.map((b) {
      if (b is Map<String, dynamic>) {
        return WorkspaceBranchInfo.fromJson(b);
      }
      return WorkspaceBranchInfo.fromJson(Map<String, dynamic>.from(b as Map));
    }).toList();

    return WorkspaceListBranchesResult(
      branches: branches,
      currentBranch: json['currentBranch'] as String?,
      detached: json['detached'] as bool? ?? false,
      headShortSha: json['headShortSha'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'branches': branches.map((b) => b.toJson()).toList(),
    if (currentBranch != null) 'currentBranch': currentBranch,
    'detached': detached,
    if (headShortSha != null) 'headShortSha': headShortSha,
  };
}

class WorkspaceSwitchBranchResult {
  final String currentBranch;
  final bool stashed;
  final String? stashMessage;

  const WorkspaceSwitchBranchResult({
    required this.currentBranch,
    required this.stashed,
    this.stashMessage,
  });

  factory WorkspaceSwitchBranchResult.fromJson(Map<String, dynamic> json) {
    return WorkspaceSwitchBranchResult(
      currentBranch: json['currentBranch'] as String? ?? '',
      stashed: json['stashed'] as bool? ?? false,
      stashMessage: json['stashMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'currentBranch': currentBranch,
    'stashed': stashed,
    if (stashMessage != null) 'stashMessage': stashMessage,
  };
}

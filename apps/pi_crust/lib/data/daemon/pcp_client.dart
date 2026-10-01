import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';

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

  final _connectionStateController = StreamController<DaemonConnectionState>.broadcast();
  Stream<DaemonConnectionState> get connectionStateStream => _connectionStateController.stream;
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

  // Attached sessions with lastSeq
  final _attachedSessions = <String, int?>{};

  PcpClient({
    this.host = '127.0.0.1',
    required this.port,
    required this.token,
    this.rediscover,
  });

  void connect() {
    if (_disposed) return;
    _setConnectionState(DaemonConnectionState.connecting);

    try {
      final uri = Uri.parse('ws://$host:$port');
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
          'name': 'pi_crust_flutter',
          'version': '0.1.0',
          'platform': defaultTargetPlatform.name,
        },
        'encoding': 'json',
        'capabilities': ['replay.v1', 'ui.claim.v1', 'workspace.v1'],
      }
    };
    _sendRaw(jsonEncode(hello));
  }

  void _onMessage(dynamic raw) {
    try {
      final map = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final kind = map['kind'] as String?;

      if (kind == 'welcome') {
        _setConnectionState(DaemonConnectionState.connected);
        _reconnectDelaySeconds = 1;

        // Re-attach all active sessions
        for (final entry in _attachedSessions.entries) {
          attach(entry.key, lastSeq: entry.value);
        }

        // Re-send in-flight commands with identical commandId
        for (final cmd in _inFlightCommands.values) {
          _sendRaw(PcpCodec.encodeMessage(cmd));
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
          'payload': {}
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
            completer.completeError(StateError(payload['error']?.toString() ?? 'Command failed'));
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
          completer.completeError(Exception(payload['message'] ?? 'PCP Error'));
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
          if (event.type != 'journal.gap' && lastSeq != null && event.seq <= lastSeq) {
            return;
          }
          _attachedSessions[sessionId] = event.seq;
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
    _cleanupChannel();
    _scheduleReconnect();
  }

  void _onDone() {
    _cleanupChannel();
    _scheduleReconnect();
  }

  void _cleanupChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setConnectionState(DaemonConnectionState.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () async {
      _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 15);
      try {
        final endpoint = await rediscover?.call();
        if (_disposed) return;
        if (endpoint != null && (endpoint.port != port || endpoint.token != token)) {
          // A new daemon cannot deduplicate uncertain commands from the old daemon.
          for (final pending in _pendingCommands.values) {
            pending.completeError(StateError('Daemon restarted. Check session state before retrying the command.'));
          }
          _pendingCommands.clear();
          _inFlightCommands.clear();
          port = endpoint.port;
          token = endpoint.token;
        }
      } catch (_) { /* A later reconnect will retry discovery. */ }
      if (!_disposed) connect();
    });
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
    unawaited(sendCommand(cmd).catchError((Object error) {
      if (kDebugMode) debugPrint('Session attach failed: $error');
      return <String, dynamic>{};
    }));
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

  Future<Map<String, dynamic>> setModel(String sessionId, String provider, String modelId) {
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

  Future<Map<String, dynamic>> setThinkingLevel(String sessionId, String level) {
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

  Future<Map<String, dynamic>> claimUiRequest(String sessionId, String requestId) {
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

  Future<Map<String, dynamic>> continueSession(String sessionId, {bool confirmed = false}) {
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

  Future<Map<String, dynamic>> refreshWorkspace(String sessionId, {String? cwd}) {
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

  Future<Map<String, dynamic>> getWorkspaceDiff(String sessionId, {String? filePath}) {
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
      payload: {
        'query': ?query,
        'limit': ?limit,
      },
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

  Future<Map<String, dynamic>> forkSession(String sessionId, {String? entryId}) {
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

  Stream<PcpEvent> events(String sessionId) {
    return _eventControllers.putIfAbsent(
      sessionId,
      () => StreamController<PcpEvent>.broadcast(),
    ).stream;
  }

  Stream<PcpSnapshot> snapshots(String sessionId) {
    return _snapshotControllers.putIfAbsent(
      sessionId,
      () => StreamController<PcpSnapshot>.broadcast(),
    ).stream;
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

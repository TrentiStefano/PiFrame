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
  final int port;
  final String token;

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
          completer.complete(payload);
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
        if (_snapshotControllers.containsKey(sessionId)) {
          _snapshotControllers[sessionId]!.add(snapshot);
        }
        return;
      }

      if (kind == 'event') {
        final event = PcpCodec.decodeEvent(map);
        final sessionId = event.sessionId;
        _attachedSessions[sessionId] = event.seq;
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
    _channel = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setConnectionState(DaemonConnectionState.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaySeconds), () {
      _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 15);
      connect();
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
      commandId: 'att_${DateTime.now().millisecondsSinceEpoch}',
      type: 'session.attach',
      payload: {'lastSeq': lastSeq},
    );
    sendCommand(cmd);
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
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanupChannel();
    _connectionStateController.close();
    for (final c in _eventControllers.values) {
      c.close();
    }
    for (final c in _snapshotControllers.values) {
      c.close();
    }
  }
}

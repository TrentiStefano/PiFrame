import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';

void main() {
  late HttpServer server;
  late PcpClient client;
  late WebSocket socket;
  late StreamSubscription subscription;
  final commands = <Map<String, dynamic>>[];

  setUp(() async {
    commands.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ready = Completer<void>();
    subscription = server.listen((request) async {
      socket = await WebSocketTransformer.upgrade(request);
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (frame['kind'] == 'hello') {
          socket.add(jsonEncode({'kind': 'welcome'}));
        } else if (frame['kind'] == 'command') {
          commands.add(frame);
        }
      });
    });
    client = PcpClient(port: server.port, token: 'test');
    client.connectionStateStream.listen((state) {
      if (state == DaemonConnectionState.connected && !ready.isCompleted) {
        ready.complete();
      }
    });
    client.connect();
    await ready.future.timeout(const Duration(seconds: 3));
  });

  tearDown(() async {
    client.dispose();
    await socket.close();
    await subscription.cancel();
    await server.close(force: true);
  });

  test('failed results reject instead of hiding daemon errors', () async {
    final result = client.listSessions();
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {'state': 'failed', 'error': 'Worker unavailable'},
    }));
    await assertion;
  });

  test('rapid same-type commands have distinct IDs and both complete', () async {
    final first = client.listSessions();
    final second = client.listSessions();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(commands.length, 2);
    expect(commands[0]['commandId'], isNot(commands[1]['commandId']));
    for (final command in commands) {
      socket.add(jsonEncode({
        'kind': 'result',
        'commandId': command['commandId'],
        'payload': {'state': 'completed', 'data': {'sessions': []}},
      }));
    }
    await Future.wait([first, second]);
  });

  test('dispose rejects pending commands', () async {
    final result = client.listSessions();
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    client.dispose();
    await assertion;
  });
}

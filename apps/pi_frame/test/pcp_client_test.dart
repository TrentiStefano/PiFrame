import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';

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
    socket.add(
      jsonEncode({
        'kind': 'result',
        'commandId': commands.single['commandId'],
        'payload': {'state': 'failed', 'error': 'Worker unavailable'},
      }),
    );
    await assertion;
  });

  test(
    'rapid same-type commands have distinct IDs and both complete',
    () async {
      final first = client.listSessions();
      final second = client.listSessions();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.length, 2);
      expect(commands[0]['commandId'], isNot(commands[1]['commandId']));
      for (final command in commands) {
        socket.add(
          jsonEncode({
            'kind': 'result',
            'commandId': command['commandId'],
            'payload': {
              'state': 'completed',
              'data': {'sessions': []},
            },
          }),
        );
      }
      await Future.wait([first, second]);
    },
  );

  test(
    'workspace commands use the active session and preserve validated payloads',
    () async {
      final requests = <Future<Map<String, dynamic>>>[
        client.listWorkspaceFiles('session-a'),
        client.readWorkspaceFile('session-a', 'lib/main.dart'),
        client.saveWorkspaceFile('session-a', {
          'path': 'lib/main.dart',
          'content': 'updated',
          'revision': List.filled(64, 'a').join(),
        }),
        client.workspaceGitAction('session-a', {
          'action': 'commit',
          'paths': ['lib/main.dart'],
          'expectedStagedPaths': ['lib/main.dart'],
          'message': 'Update main',
        }),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.map((command) => command['type']).toList(), [
        'workspace.listFiles',
        'workspace.readFile',
        'workspace.saveFile',
        'workspace.gitAction',
      ]);
      for (var index = 0; index < commands.length; index++) {
        expect(commands[index]['sessionId'], 'session-a');
        socket.add(
          jsonEncode({
            'kind': 'result',
            'commandId': commands[index]['commandId'],
            'payload': {'state': 'completed', 'data': {}},
          }),
        );
      }
      await Future.wait(requests);
      expect(commands[1]['payload']['path'], 'lib/main.dart');
      expect(commands[2]['payload']['revision'], List.filled(64, 'a').join());
      expect(commands[3]['payload']['expectedStagedPaths'], ['lib/main.dart']);
    },
  );

  test('context settings serialize backend command payloads', () async {
    final limitFuture = client.setContextWindowOverride('session-a', 195000);
    final reserveFuture = client.setCompactionReservePercent('session-a', 5.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(commands.map((command) => command['type']).toList(), [
      'agent.setContextWindowOverride',
      'agent.setCompactionReservePercent',
    ]);
    expect(commands[0]['payload'], {'limit': 195000});
    expect(commands[1]['payload'], {'percent': 5.0});
    for (final command in commands) {
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': command['commandId'],
          'payload': {
            'state': 'completed',
            'data': {
              'contextWindowOverride': 195000,
              'compactionReservePercent': 5.0,
            },
          },
        }),
      );
    }
    await Future.wait([limitFuture, reserveFuture]);
  });

  test('Pi authentication commands carry no credential data', () async {
    final login = client.piAuthLogin('session-a');
    final logout = client.piAuthLogout('session-a');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(commands.map((command) => command['type']).toList(), [
      'agent.authLogin',
      'agent.authLogout',
    ]);
    expect(commands.every((command) => command['payload'].isEmpty), isTrue);
    expect(
      commands.every((command) => command['sessionId'] == 'session-a'),
      isTrue,
    );
    for (final command in commands) {
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': command['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'started': true},
          },
        }),
      );
    }
    await Future.wait([login, logout]);
  });

  test('subagents unwrap daemon data with persisted model and cost', () async {
    final result = client.getSubagents('parent');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(commands.single['type'], 'session.subagents');
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {
        'state': 'completed',
        'data': {
          'subagents': [
            {'id': 'child', 'model': 'actual-model', 'cost': 0.0175},
          ],
        },
      },
    }));
    expect(await result, [
      {'id': 'child', 'model': 'actual-model', 'cost': 0.0175},
    ]);
  });

  test('subagents propagate failed responses instead of returning empty', () async {
    final result = client.getSubagents('parent');
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {'state': 'failed', 'error': 'Unavailable'},
    }));
    await assertion;
  });

  test('subagents reject malformed data instead of returning empty', () async {
    final result = client.getSubagents('parent');
    final assertion = expectLater(result, throwsA(isA<FormatException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {'state': 'completed', 'data': {}},
    }));
    await assertion;
  });

  test('dispose rejects pending commands', () async {
    final result = client.listSessions();
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    client.dispose();
    await assertion;
  });

  test(
    'remote connection commands format correct payloads and complete',
    () async {
      final statusFuture = client.getRemoteStatus();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.getStatus');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'enabled': false, 'state': 'stopped'},
          },
        }),
      );
      final status = await statusFuture;
      final statusData = status['data'] as Map<String, dynamic>;
      expect(statusData['enabled'], false);

      final startFuture = client.startRemoteTunnel(
        tunnelProvider: 'cloudflared',
        customUrl: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.start');
      expect(commands.last['payload']['tunnelProvider'], 'cloudflared');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'enabled': true, 'state': 'running'},
          },
        }),
      );
      await startFuture;

      final pairFuture = client.generateRemotePairing(ttlMs: 300000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.generatePairing');
      expect(commands.last['payload']['ttlMs'], 300000);
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'secret': 'pair_tok_test'},
          },
        }),
      );
      final pair = await pairFuture;
      final pairData = pair['data'] as Map<String, dynamic>;
      expect(pairData['secret'], 'pair_tok_test');

      final optFuture = client.setRemoteOptions(defaultMode: 'control');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.setOptions');
      expect(commands.last['payload']['defaultMode'], 'control');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {'state': 'completed', 'data': {}},
        }),
      );
      await optFuture;

      final modeFuture = client.setRemoteDeviceMode(
        deviceId: 'dev_test_123',
        mode: 'control',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.setDeviceMode');
      expect(commands.last['payload']['deviceId'], 'dev_test_123');
      expect(commands.last['payload']['mode'], 'control');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'ok': true},
          },
        }),
      );
      await modeFuture;

      final revFuture = client.revokeRemoteDevice('dev_test_123');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.revokeDevice');
      expect(commands.last['payload']['deviceId'], 'dev_test_123');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'ok': true},
          },
        }),
      );
      await revFuture;

      final stopFuture = client.stopRemoteTunnel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.stop');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'enabled': false, 'state': 'stopped'},
          },
        }),
      );
      await stopFuture;
    },
  );

  test('listBranches and switchBranch format payloads and parse typed results', () async {
    final listFuture = client.listBranches('session-b');
    final switchFuture = client.switchBranch('session-b', 'feature/test', onDirty: 'stash');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(commands.map((c) => c['type']).toList(), [
      'workspace.listBranches',
      'workspace.switchBranch',
    ]);
    expect(commands[0]['sessionId'], 'session-b');
    expect(commands[1]['sessionId'], 'session-b');
    expect(commands[1]['payload'], {'branch': 'feature/test', 'onDirty': 'stash'});

    // Reply to listBranches
    socket.add(
      jsonEncode({
        'kind': 'result',
        'commandId': commands[0]['commandId'],
        'payload': {
          'state': 'completed',
          'data': {
            'branches': [
              {
                'name': 'main',
                'isCurrent': true,
                'upstream': 'origin/main',
                'ahead': 1,
                'behind': 0,
                'lastCommitUnix': 1700000000,
              },
            ],
            'currentBranch': 'main',
            'detached': false,
            'headShortSha': 'abc1234',
          },
        },
      }),
    );

    // Reply to switchBranch
    socket.add(
      jsonEncode({
        'kind': 'result',
        'commandId': commands[1]['commandId'],
        'payload': {
          'state': 'completed',
          'data': {
            'currentBranch': 'feature/test',
            'stashed': true,
            'stashMessage': 'piframe: before switching',
          },
        },
      }),
    );

    final listRes = await listFuture;
    final switchRes = await switchFuture;

    expect(listRes.branches.length, 1);
    expect(listRes.branches[0].name, 'main');
    expect(listRes.branches[0].isCurrent, isTrue);
    expect(listRes.branches[0].ahead, 1);
    expect(listRes.currentBranch, 'main');
    expect(listRes.detached, isFalse);
    expect(listRes.headShortSha, 'abc1234');

    expect(switchRes.currentBranch, 'feature/test');
    expect(switchRes.stashed, isTrue);
    expect(switchRes.stashMessage, 'piframe: before switching');
  });

  test(
    'error-then-result ordering yields PcpException with code/details (WORKSPACE_DIRTY details)',
    () async {
      final switchFuture = client.switchBranch('session-b', 'dirty-branch');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(commands.single['type'], 'workspace.switchBranch');

      // Daemon sends detailed kind:'error' envelope FIRST
      socket.add(
        jsonEncode({
          'kind': 'error',
          'commandId': commands.single['commandId'],
          'payload': {
            'code': 'WORKSPACE_DIRTY',
            'message': 'Working directory has uncommitted changes',
            'details': {
              'changedFiles': 3,
              'untrackedFiles': 1,
            },
          },
        }),
      );

      // Followed by terminal kind:'result' envelope SECOND
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.single['commandId'],
          'payload': {
            'state': 'rejected',
            'error': 'Working directory has uncommitted changes',
          },
        }),
      );

      try {
        await switchFuture;
        fail('Expected PcpException');
      } catch (e) {
        expect(e, isA<PcpException>());
        expect(e, isA<StateError>());
        expect(e, isA<Exception>());
        final pcpErr = e as PcpException;
        expect(pcpErr.code, 'WORKSPACE_DIRTY');
        expect(pcpErr.changedFiles, 3);
        expect(pcpErr.untrackedFiles, 1);
        expect(pcpErr.message, 'Working directory has uncommitted changes');
      }
    },
  );

  test('result-only failure yields PcpException with message', () async {
    final switchFuture = client.switchBranch('session-c', 'some-branch');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Simulate daemon sending only a kind:'result' failure without preceding error envelope
    socket.add(
      jsonEncode({
        'kind': 'result',
        'commandId': commands.single['commandId'],
        'payload': {
          'state': 'failed',
          'error': 'Daemon failed to switch branch',
        },
      }),
    );

    try {
      await switchFuture;
      fail('Expected PcpException');
    } catch (e) {
      expect(e, isA<PcpException>());
      expect(e, isA<StateError>());
      expect(e, isA<Exception>());
      final pcpErr = e as PcpException;
      expect(pcpErr.message, 'Daemon failed to switch branch');
      expect(pcpErr.code, '');
    }
  });

  test('PcpException toString() starts with "Bad state: " and strips cleanly', () {
    final err = PcpException(
      'Working directory has uncommitted changes',
      code: 'WORKSPACE_DIRTY',
      details: {'changedFiles': 2},
    );
    expect(err.toString(), startsWith('Bad state: '));
    expect(err.toString(), 'Bad state: Working directory has uncommitted changes');

    // Existing caller regex stripping ^(Bad state|Exception):\s*
    final stripped = err.toString().replaceFirst(
      RegExp(r'^(Bad state|Exception):\s*'),
      '',
    );
    expect(stripped, 'Working directory has uncommitted changes');
  });
}

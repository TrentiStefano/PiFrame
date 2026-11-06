import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/side/side_panel.dart';
import 'package:pi_frame/features/side/side_provider.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class FakeSidePcpClient extends PcpClient {
  FakeSidePcpClient() : super(port: 0, token: 'fake');

  final List<PcpCommand> sentCommands = [];
  final Map<String, StreamController<PcpEvent>> _eventControllers = {};
  final Map<String, StreamController<PcpSnapshot>> _snapshotControllers = {};

  @override
  Stream<PcpEvent> events(String sessionId) {
    return _eventControllers
        .putIfAbsent(sessionId, () => StreamController<PcpEvent>.broadcast())
        .stream;
  }

  @override
  Stream<PcpSnapshot> snapshots(String sessionId) {
    return _snapshotControllers
        .putIfAbsent(sessionId, () => StreamController<PcpSnapshot>.broadcast())
        .stream;
  }

  void emitEvent(String sessionId, PcpEvent event) {
    _eventControllers
        .putIfAbsent(sessionId, () => StreamController<PcpEvent>.broadcast())
        .add(event);
  }

  void emitSnapshot(String sessionId, PcpSnapshot snapshot) {
    _snapshotControllers
        .putIfAbsent(sessionId, () => StreamController<PcpSnapshot>.broadcast())
        .add(snapshot);
  }

  @override
  void attach(String sessionId, {int? lastSeq}) {}

  @override
  Future<Map<String, dynamic>> openSide(
    String sessionId, {
    String? question,
  }) async {
    final cmd = PcpCommand.sideOpen(
      commandId: 'cmd_side_open_${sentCommands.length}',
      sessionId: sessionId,
      question: question,
    );
    sentCommands.add(cmd);
    return {
      'sideId': 'side_test_1',
      'streamId': 'stream_test_1',
      'model': 'gpt-4o',
    };
  }

  @override
  Future<Map<String, dynamic>> sidePrompt(
    String sideId,
    String text,
  ) async {
    final cmd = PcpCommand.sidePrompt(
      commandId: 'cmd_side_prompt_${sentCommands.length}',
      sideId: sideId,
      text: text,
    );
    sentCommands.add(cmd);
    return {'prompted': true};
  }

  @override
  Future<Map<String, dynamic>> sideAbort(String sideId) async {
    final cmd = PcpCommand.sideAbort(
      commandId: 'cmd_side_abort_${sentCommands.length}',
      sideId: sideId,
    );
    sentCommands.add(cmd);
    return {'aborted': true};
  }

  @override
  Future<Map<String, dynamic>> sideClose(String sideId) async {
    final cmd = PcpCommand.sideClose(
      commandId: 'cmd_side_close_${sentCommands.length}',
      sideId: sideId,
    );
    sentCommands.add(cmd);
    return {'closed': true};
  }

  @override
  Future<Map<String, dynamic>> sendPrompt(
    String sessionId,
    String text, {
    String? streamingBehavior,
    List<dynamic>? images,
  }) async {
    final cmd = PcpCommand(
      protocol: 1,
      id: 'cmd_prompt_${sentCommands.length}',
      ts: DateTime.now().millisecondsSinceEpoch,
      sessionId: sessionId,
      commandId: 'cmd_agent_prompt_${sentCommands.length}',
      type: 'agent.prompt',
      payload: {'text': text},
    );
    sentCommands.add(cmd);
    return {'accepted': true};
  }

  @override
  Future<Map<String, dynamic>> getCommands(String sessionId) async {
    return {'commands': []};
  }

  @override
  Future<Map<String, dynamic>> getAvailableModels(String sessionId) async {
    return {'models': []};
  }

  @override
  Future<Map<String, dynamic>> getAvailableThinkingLevels(
    String sessionId,
  ) async {
    return {'levels': []};
  }

  @override
  Future<Map<String, dynamic>> listSessions({String? query, int? limit}) async {
    return {
      'sessions': [
        {'id': 'parent_session', 'name': 'Main Session', 'cwd': '/workspace'},
      ],
    };
  }

  @override
  DaemonConnectionState get state => DaemonConnectionState.connected;
}

Widget _wrapWithTokens({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSidePcpClient fakeClient;

  setUp(() {
    fakeClient = FakeSidePcpClient();
  });

  group('Side Conversation Slash Commands & Isolation', () {
    testWidgets('/side opens side with question, never sends agent.prompt', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithTokens(
          child: const Composer(sessionId: 'parent_session'),
          overrides: [
            pcpClientProvider.overrideWithValue(fakeClient),
            activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, '/side what is this function doing?');
      await tester.pumpAndSettle();

      // Submit via icon button
      final sendBtn = find.byIcon(Icons.arrow_upward);
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      // Check commands sent
      final sideOpenCmds =
          fakeClient.sentCommands.where((c) => c.type == 'side.open').toList();
      final agentPromptCmds = fakeClient.sentCommands
          .where((c) => c.type == 'agent.prompt')
          .toList();

      expect(sideOpenCmds, hasLength(1));
      expect(sideOpenCmds.first.sessionId, 'parent_session');
      expect(
        sideOpenCmds.first.payload['question'],
        'what is this function doing?',
      );
      expect(agentPromptCmds, isEmpty, reason: 'Must never send agent.prompt');
    });

    testWidgets('/btw opens side with question, never sends agent.prompt', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithTokens(
          child: const Composer(sessionId: 'parent_session'),
          overrides: [
            pcpClientProvider.overrideWithValue(fakeClient),
            activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, '/btw can you explain this test?');
      await tester.pumpAndSettle();

      final sendBtn = find.byIcon(Icons.arrow_upward);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      final sideOpenCmds =
          fakeClient.sentCommands.where((c) => c.type == 'side.open').toList();
      final agentPromptCmds = fakeClient.sentCommands
          .where((c) => c.type == 'agent.prompt')
          .toList();

      expect(sideOpenCmds, hasLength(1));
      expect(sideOpenCmds.first.sessionId, 'parent_session');
      expect(
        sideOpenCmds.first.payload['question'],
        'can you explain this test?',
      );
      expect(agentPromptCmds, isEmpty, reason: 'Must never send agent.prompt');
    });

    testWidgets('Slash menu lists /side and /btw with description', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithTokens(
          child: const Composer(sessionId: 'parent_session'),
          overrides: [
            pcpClientProvider.overrideWithValue(fakeClient),
            activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();

      expect(find.text('/side [question]'), findsOneWidget);
      expect(find.text('/btw [question]'), findsOneWidget);
      expect(
        find.text('Conversazione laterale in sola lettura'),
        findsNWidgets(2),
      );
    });

    testWidgets(
      'Side stream events update side state but NOT main session state (isolation)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            pcpClientProvider.overrideWithValue(fakeClient),
            activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          ],
        );
        addTearDown(container.dispose);

        // Open side conversation
        final sideNotifier =
            container.read(sideThreadFamily('parent_session').notifier);
        await sideNotifier.openSide(question: 'Explain isolation');

        final sideThread = container.read(sideThreadFamily('parent_session'));
        expect(sideThread.status, 'active');
        expect(sideThread.streamId, 'stream_test_1');

        // Initialize main session state notifier
        container.read(sessionStateFamily('parent_session').notifier);

        // Emit side opened event on stream_test_1
        fakeClient.emitEvent(
          'stream_test_1',
          SideOpenedEvent(
            protocol: 1,
            id: 'evt_open_1',
            ts: 100,
            sessionId: 'stream_test_1',
            seq: 1,
            payload: {
              'sideId': 'side_test_1',
              'parentSessionId': 'parent_session',
              'model': 'claude-3-5-sonnet',
            },
          ),
        );

        // Emit turn started and text delta on stream_test_1
        fakeClient.emitEvent(
          'stream_test_1',
          TurnStartedEvent(
            protocol: 1,
            id: 'evt_turn_1',
            ts: 110,
            sessionId: 'stream_test_1',
            seq: 2,
            payload: {'turnId': 'turn_1'},
          ),
        );

        fakeClient.emitEvent(
          'stream_test_1',
          TextStartedEvent(
            protocol: 1,
            id: 'evt_txt_start_1',
            ts: 120,
            sessionId: 'stream_test_1',
            seq: 3,
            payload: {'blockIndex': 0},
          ),
        );

        fakeClient.emitEvent(
          'stream_test_1',
          TextDeltaEvent(
            protocol: 1,
            id: 'evt_delta_1',
            ts: 130,
            sessionId: 'stream_test_1',
            seq: 4,
            payload: {'blockIndex': 0, 'delta': 'Isolated side response text'},
          ),
        );

        fakeClient.emitEvent(
          'stream_test_1',
          TextCompletedEvent(
            protocol: 1,
            id: 'evt_txt_end_1',
            ts: 140,
            sessionId: 'stream_test_1',
            seq: 5,
            payload: {'blockIndex': 0, 'text': 'Isolated side response text'},
          ),
        );

        fakeClient.emitEvent(
          'stream_test_1',
          MessageCompletedEvent(
            protocol: 1,
            id: 'evt_msg_1',
            ts: 150,
            sessionId: 'stream_test_1',
            seq: 6,
            payload: {
              'messageId': 'msg_side_1',
              'role': 'assistant',
              'text': 'Isolated side response text',
            },
          ),
        );

        await tester.pump();

        // Check side session state
        final sideSession =
            container.read(sideSessionFamily('parent_session'));
        expect(sideSession.entries, hasLength(1));
        expect(sideSession.entries.first.text, 'Isolated side response text');
        expect(sideSession.readOnly, isTrue);

        // Check main session state: MUST NOT receive side events!
        final mainSession =
            container.read(sessionStateFamily('parent_session'));
        expect(
          mainSession.entries,
          isEmpty,
          reason: 'Main session state must never receive side events',
        );
        expect(
          mainSession.currentStreamingText,
          isEmpty,
          reason: 'Main session must not stream side text',
        );
      },
    );
  });

  group('Side Panel UI & Actions', () {
    testWidgets('Side panel displays read-only badge, model and note', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(fakeClient),
          activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
        ],
      );
      addTearDown(container.dispose);

      // Open side panel
      final sideNotifier =
          container.read(sideThreadFamily('parent_session').notifier);
      await sideNotifier.openSide(question: 'test question');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SidePanel(sessionId: 'parent_session'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only badge visible
      expect(find.byKey(const ValueKey('side-read-only-badge')), findsOneWidget);
      expect(find.text('Side · read-only'), findsOneWidget);

      // Model visible
      expect(find.text('gpt-4o'), findsOneWidget);

      // Note visible
      expect(
        find.text('Non fa parte della conversazione principale'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('Stop sends side.abort', (tester) async {
      final container = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(fakeClient),
          activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
        ],
      );
      addTearDown(container.dispose);

      final sideNotifier =
          container.read(sideThreadFamily('parent_session').notifier);
      await sideNotifier.openSide(question: 'Long running question');

      // Set side session to streaming
      container.read(sideSessionFamily('parent_session').notifier).state =
          const SessionState(
        sessionId: 'stream_test_1',
        cwd: '',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating...'},
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SidePanel(sessionId: 'parent_session'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stop button should be visible in header
      final stopBtn = find.byKey(const ValueKey('side-abort-btn'));
      expect(stopBtn, findsOneWidget);

      await tester.tap(stopBtn);
      await tester.pumpAndSettle();

      final abortCmds =
          fakeClient.sentCommands.where((c) => c.type == 'side.abort').toList();
      expect(abortCmds, hasLength(1));
      expect(abortCmds.first.sessionId, 'side_test_1');
    });

    testWidgets(
      'Close sends side.close after confirmation and confirms nothing is lost from main',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            pcpClientProvider.overrideWithValue(fakeClient),
            activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          ],
        );
        addTearDown(container.dispose);

        final sideNotifier =
            container.read(sideThreadFamily('parent_session').notifier);
        await sideNotifier.openSide();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [FrameTokens.dark],
              ),
              home: const Scaffold(
                body: SidePanel(sessionId: 'parent_session'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap close button in header
        final closeBtn = find.byKey(const ValueKey('side-close-btn'));
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Chiudi conversazione laterale'), findsOneWidget);
        expect(
          find.text('Nessun dato andrà perso nella conversazione principale.'),
          findsOneWidget,
        );

        // Confirm close
        final confirmBtn = find.byKey(const ValueKey('side-confirm-close-btn'));
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        final closeCmds =
            fakeClient.sentCommands.where((c) => c.type == 'side.close').toList();
        expect(closeCmds, hasLength(1));
        expect(closeCmds.first.sessionId, 'side_test_1');

        // Side panel should be closed now
        final sideThread = container.read(sideThreadFamily('parent_session'));
        expect(sideThread.isClosed, isTrue);
        expect(sideThread.isOpen, isFalse);
      },
    );

    testWidgets(
      'Insert into composer only on click appends text (never auto)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            pcpClientProvider.overrideWithValue(fakeClient),
            activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          ],
        );
        addTearDown(container.dispose);

        final sideNotifier =
            container.read(sideThreadFamily('parent_session').notifier);
        await sideNotifier.openSide();

        // Populate side session with assistant reply
        container.read(sideSessionFamily('parent_session').notifier).state =
            const SessionState(
          sessionId: 'stream_test_1',
          cwd: '',
          entries: [
            SessionEntry(
              id: 'side_reply_1',
              role: 'assistant',
              text: 'Consider refactoring this helper method.',
              timestamp: 1000,
            ),
          ],
        );

        // Pre-populate main composer draft
        container
            .read(composerDraftProvider('parent_session').notifier)
            .state = 'Initial draft';

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [FrameTokens.dark],
              ),
              home: const Scaffold(
                body: SidePanel(sessionId: 'parent_session'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Before click: draft is strictly initial draft (NEVER auto inserted)
        expect(
          container.read(composerDraftProvider('parent_session')),
          'Initial draft',
        );

        // Find insert button
        final insertBtn =
            find.byKey(const ValueKey('side-insert-into-composer-side_reply_1'));
        expect(insertBtn, findsOneWidget);

        // Click insert button
        await tester.tap(insertBtn);
        await tester.pumpAndSettle();

        // After click: appended to main draft
        expect(
          container.read(composerDraftProvider('parent_session')),
          'Initial draft\n\nConsider refactoring this helper method.',
        );
      },
    );

    testWidgets('side.closed idle shows notice', (tester) async {
      final container = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(fakeClient),
          activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
        ],
      );
      addTearDown(container.dispose);

      final sideNotifier =
          container.read(sideThreadFamily('parent_session').notifier);
      await sideNotifier.openSide();

      // Emit SideClosedEvent with idle reason
      fakeClient.emitEvent(
        'stream_test_1',
        const SideClosedEvent(
          protocol: 1,
          id: 'evt_closed_1',
          ts: 200,
          sessionId: 'stream_test_1',
          seq: 10,
          payload: {
            'sideId': 'side_test_1',
            'reason': 'idle',
          },
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: SidePanel(sessionId: 'parent_session'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Notice should be visible
      expect(find.byKey(const ValueKey('side-closed-notice')), findsOneWidget);
      expect(
        find.text('Conversazione laterale chiusa per inattività.'),
        findsOneWidget,
      );
    });

    testWidgets('Shortcut Ctrl/Cmd+Shift+B toggles side panel', (tester) async {
      final container = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(fakeClient),
          activeSessionIdProvider.overrideWith((ref) => 'parent_session'),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
          sessionListProvider.overrideWith(
            (ref) async => [
              {
                'id': 'parent_session',
                'name': 'Main Session',
                'cwd': '/workspace',
              },
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(sideThreadFamily('parent_session')).isOpen, isFalse);

      // Simulate Ctrl+Shift+B key combination
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(sideThreadFamily('parent_session')).isOpen, isTrue);

      // Simulate again to toggle off
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(sideThreadFamily('parent_session')).isOpen, isFalse);
    });
  });
}

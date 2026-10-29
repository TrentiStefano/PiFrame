import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class RejectingSession extends SessionStateNotifier {
  RejectingSession() : super('rejecting', null);
}

class DeferredSession extends SessionStateNotifier {
  Completer<void> completion = Completer<void>();
  int calls = 0;
  DeferredSession() : super('pending', null);
  @override
  Future<void> sendPrompt(String text, {String? streamingBehavior}) {
    calls++;
    return completion.future;
  }
}

class BuiltinCommandSession extends SessionStateNotifier {
  int loginCalls = 0;
  int logoutCalls = 0;
  BuiltinCommandSession() : super('builtin', null);

  @override
  Future<void> piAuthLogin() async {
    loginCalls++;
  }

  @override
  Future<void> piAuthLogout() async {
    logoutCalls++;
  }

  @override
  Future<List<Map<String, dynamic>>> getCommands() async => [
    {
      'name': 'settings',
      'description': 'Open settings menu',
      'source': 'builtin',
    },
    {'name': 'share', 'description': 'Share session', 'source': 'builtin'},
    {
      'name': 'login',
      'description': 'Authenticate with a provider',
      'source': 'builtin',
    },
    {
      'name': 'logout',
      'description': 'Remove provider credentials',
      'source': 'builtin',
    },
    {'name': 'caveman', 'description': 'Caveman mode', 'source': 'extension'},
  ];
}

void main() {
  testWidgets('Pi built-ins appear in slash menu and run as local actions', (
    tester,
  ) async {
    final session = BuiltinCommandSession();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('builtin').overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: Composer(sessionId: 'builtin')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Composer)),
    );

    await tester.enterText(find.byType(TextField), '/');
    await tester.pumpAndSettle();
    expect(find.text('/settings'), findsOneWidget);
    expect(find.text('/share'), findsOneWidget);
    expect(find.text('/login'), findsOneWidget);
    expect(find.text('/logout'), findsOneWidget);
    expect(find.text('/caveman'), findsOneWidget);

    await tester.tap(find.text('/settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(container.read(showSettingsProvider), isTrue);
    expect(session.state.entries, isEmpty);

    await tester.enterText(find.byType(TextField), '/login');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(session.loginCalls, 1);
    expect(session.state.entries, isEmpty);

    await tester.enterText(find.byType(TextField), '/logout');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(session.logoutCalls, 1);
    expect(session.state.entries, isEmpty);
  });

  testWidgets(
    'pending send survives session switch and updates restored draft safely',
    (tester) async {
      final session = DeferredSession();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            activeSessionIdProvider.overrideWith((ref) => 'pending'),
            sessionStateFamily('pending').overrideWith((ref) => session),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  final id = ref.watch(activeSessionIdProvider)!;
                  return Composer(key: ValueKey(id), sessionId: id);
                },
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Composer)),
      );
      await tester.enterText(find.byType(TextField), 'Pending draft');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();
      expect(find.text('Pending draft'), findsNothing);
      expect(container.read(composerDraftProvider('pending')), isEmpty);
      container.read(activeSessionIdProvider.notifier).state = 'B';
      await tester.pump();
      container.read(activeSessionIdProvider.notifier).state = 'pending';
      await tester.pump();
      final sendButton = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_upward),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(sendButton.onPressed, isNull);
      expect(session.calls, 1);
      session.completion.complete();
      await tester.pump();
      expect(find.text('Pending draft'), findsNothing);
      expect(container.read(composerDraftProvider('pending')), isEmpty);

      session.completion = Completer<void>();
      await tester.enterText(find.byType(TextField), 'Second draft');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Newer edit');
      container.read(activeSessionIdProvider.notifier).state = 'B';
      await tester.pump();
      container.read(activeSessionIdProvider.notifier).state = 'pending';
      await tester.pump();
      session.completion.complete();
      await tester.pump();
      expect(find.text('Newer edit'), findsOneWidget);
      expect(container.read(composerDraftProvider('pending')), 'Newer edit');
    },
  );

  testWidgets(
    'failed prompt clears composer and keeps error on message entry',
    (tester) async {
      final session = RejectingSession();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('rejecting').overrideWith((ref) => session),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(body: Composer(sessionId: 'rejecting')),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();
      expect(find.text('Keep this draft'), findsNothing);
      expect(session.state.entries.single.text, 'Keep this draft');
      expect(
        session.state.entries.single.metadata?['sendError'],
        contains('Daemon non connesso'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed message survives switching A to B to A', (tester) async {
    final session = RejectingSession();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          activeSessionIdProvider.overrideWith((ref) => 'rejecting'),
          sessionStateFamily('rejecting').overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final id = ref.watch(activeSessionIdProvider)!;
                return Composer(key: ValueKey(id), sessionId: id);
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Session A draft');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    expect(session.state.entries.single.text, 'Session A draft');
    expect(
      session.state.entries.single.metadata?['sendError'],
      contains('Daemon non connesso'),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Composer)),
    );
    container.read(activeSessionIdProvider.notifier).state = 'B';
    await tester.pump();
    expect(find.text('Session A draft'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Session B draft');
    container.read(activeSessionIdProvider.notifier).state = 'rejecting';
    await tester.pump();
    expect(find.text('Session A draft'), findsNothing);
    expect(find.text('Session B draft'), findsNothing);
    expect(session.state.entries.single.text, 'Session A draft');
  });

  testWidgets('Composer displays Invia button when agent is settled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('s_test').overrideWith(
            (ref) => SessionStateNotifier('s_test', null)
              ..state = const SessionState(
                sessionId: 's_test',
                cwd: '/test',
                agentStatus: AgentStatus.settled,
              ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: const Scaffold(body: Composer(sessionId: 's_test')),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    // Verify arrow_upward icon (Invia) is present
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    // Verify Steer and Follow-up buttons are NOT present when idle
    expect(find.text('Steer'), findsNothing);
    expect(find.text('Follow-up'), findsNothing);
  });

  testWidgets(
    'Composer displays Steer and Follow-up buttons when agent is streaming',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_test').overrideWith(
              (ref) => SessionStateNotifier('s_test', null)
                ..state = const SessionState(
                  sessionId: 's_test',
                  cwd: '/test',
                  agentStatus: AgentStatus.working,
                  streamingTextBlocks: {0: 'Hello, '},
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: const Scaffold(body: Composer(sessionId: 's_test')),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));

      // Initially minimized while streaming
      expect(
        find.byKey(const ValueKey('composer-minimized-bar')),
        findsOneWidget,
      );

      // Tap minimized bar to expand
      await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));
      await tester.pumpAndSettle();

      // Steer & Follow-up buttons should now be visible
      expect(find.text('Steer'), findsOneWidget);
      expect(find.text('Follow-up'), findsOneWidget);
      // Stop button should be visible
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    },
  );

  testWidgets('Composer displays pending queue bar when queue is non-empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('s_test').overrideWith(
            (ref) =>
                SessionStateNotifier('s_test', null)
                  ..state = const SessionState(
                    sessionId: 's_test',
                    cwd: '/test',
                    agentStatus: AgentStatus.working,
                    steeringQueue: ['Steer task 1'],
                    followUpQueue: ['Follow-up task 2'],
                  ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: const Scaffold(body: Composer(sessionId: 's_test')),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    // Initially minimized while answering/working
    expect(
      find.byKey(const ValueKey('composer-minimized-bar')),
      findsOneWidget,
    );

    // Tap minimized bar to expand
    await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('In coda (2): 1 steer, 1 follow-up'),
      findsOneWidget,
    );
    expect(find.text('Svuota coda'), findsOneWidget);
  });
}

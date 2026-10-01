import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/features/composer/composer.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class RejectingSession extends SessionStateNotifier {
  RejectingSession() : super('rejecting', null);
  @override
  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    throw StateError('Prompt rejected');
  }
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

void main() {
  testWidgets('pending send survives session switch and updates restored draft safely', (tester) async {
    final session = DeferredSession();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        activeSessionIdProvider.overrideWith((ref) => 'pending'),
        sessionStateFamily('pending').overrideWith((ref) => session),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
        home: Scaffold(body: Consumer(builder: (context, ref, child) {
          final id = ref.watch(activeSessionIdProvider)!;
          return Composer(key: ValueKey(id), sessionId: id);
        })),
      ),
    ));
    final container = ProviderScope.containerOf(tester.element(find.byType(Composer)));
    await tester.enterText(find.byType(TextField), 'Pending draft');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    container.read(activeSessionIdProvider.notifier).state = 'B';
    await tester.pump();
    container.read(activeSessionIdProvider.notifier).state = 'pending';
    await tester.pump();
    final sendButton = tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.arrow_upward), matching: find.byType(IconButton)).first);
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
  });

  testWidgets('failed prompt keeps draft and shows error', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionStateFamily('rejecting').overrideWith((ref) => RejectingSession())],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
        home: const Scaffold(body: Composer(sessionId: 'rejecting')),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.textContaining('Prompt rejected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected draft survives switching A to B to A', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        activeSessionIdProvider.overrideWith((ref) => 'rejecting'),
        sessionStateFamily('rejecting').overrideWith((ref) => RejectingSession()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
        home: Scaffold(body: Consumer(builder: (context, ref, child) {
          final id = ref.watch(activeSessionIdProvider)!;
          return Composer(key: ValueKey(id), sessionId: id);
        })),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Session A draft');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(Composer)));
    container.read(activeSessionIdProvider.notifier).state = 'B';
    await tester.pump();
    expect(find.text('Session A draft'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Session B draft');
    container.read(activeSessionIdProvider.notifier).state = 'rejecting';
    await tester.pump();
    expect(find.text('Session A draft'), findsOneWidget);
    expect(find.text('Session B draft'), findsNothing);
  });

  testWidgets('Composer displays Invia button when agent is settled', (tester) async {
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
          theme: ThemeData.dark().copyWith(
            extensions: [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: Composer(sessionId: 's_test'),
          ),
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

  testWidgets('Composer displays Steer and Follow-up buttons when agent is streaming', (tester) async {
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
          theme: ThemeData.dark().copyWith(
            extensions: [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: Composer(sessionId: 's_test'),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    // Steer & Follow-up buttons should now be visible
    expect(find.text('Steer'), findsOneWidget);
    expect(find.text('Follow-up'), findsOneWidget);
    // Stop button should be visible
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });

  testWidgets('Composer displays pending queue bar when queue is non-empty', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily('s_test').overrideWith(
            (ref) => SessionStateNotifier('s_test', null)
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
          theme: ThemeData.dark().copyWith(
            extensions: [CrustTokens.dark],
          ),
          home: const Scaffold(
            body: Composer(sessionId: 's_test'),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('In coda (2): 1 steer, 1 follow-up'), findsOneWidget);
    expect(find.text('Svuota coda'), findsOneWidget);
  });
}

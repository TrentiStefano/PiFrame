import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/composer/composer_settings.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Records what the composer sends. The field itself is real.
class _RecordingSession extends SessionStateNotifier {
  _RecordingSession(String sessionId, SessionState initial) : super(sessionId, null) {
    state = initial;
  }

  final List<String> sent = [];
  final List<String?> behaviors = [];

  @override
  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    sent.add(text);
    behaviors.add(streamingBehavior);
  }
}

/// Plan 4.3: the field stays visible for the whole run. While Pi answers, a 28 px status line
/// sits above it with the elapsed time and Interrompi. (This file replaced the old collapse-to-bar
/// behaviour, so its name is kept for history.)
void main() {
  Widget wrapComposer({required SessionState state}) {
    return ProviderScope(
      overrides: [
        sessionStateFamily('s_min_test').overrideWith(
          (ref) => SessionStateNotifier('s_min_test', null)..state = state,
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              Composer(sessionId: 's_min_test'),
            ],
          ),
        ),
      ),
    );
  }

  group('Composer stays visible while the agent answers', () {
    testWidgets('field and status line are both shown while the agent is streaming', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('composer-status-line')), findsOneWidget);
      expect(find.text('L\'agente sta rispondendo…'), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-status-interrupt')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-text-field')), findsOneWidget);
    });

    testWidgets('status line takes no space while idle', (tester) async {
      await tester.pumpWidget(wrapComposer(
        state: const SessionState(sessionId: 's_min_test', cwd: '/test', agentStatus: AgentStatus.settled),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('composer-status-line')), findsNothing);
      expect(find.byKey(const ValueKey('composer-status-idle')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('composer-status-idle'))).height, 0);
    });

    testWidgets('status line appears while running and is gone once the run settles', (tester) async {
      // The enter and exit timing is covered in composer_status_line_test.dart.
      final notifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(sessionId: 's_min_test', cwd: '/test', agentStatus: AgentStatus.settled);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionStateFamily('s_min_test').overrideWith((ref) => notifier)],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: Composer(sessionId: 's_min_test')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-status-line')), findsNothing);

      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-status-line')), findsOneWidget);

      notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.settled);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-status-line')), findsNothing);
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
    });

    testWidgets('queued steer keeps the status line and the field together', (tester) async {
      final notifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.working,
          streamingTextBlocks: {0: 'Generating answer...'},
          steeringQueue: ['please also add tests'],
        );
      final container = ProviderContainer(
        overrides: [sessionStateFamily('s_min_test').overrideWith((ref) => notifier)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: Column(children: [Expanded(child: SizedBox()), Composer(sessionId: 's_min_test')]),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('composer-status-line')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('steer-queue-item-0')), findsOneWidget);

      notifier.state = notifier.state.copyWith(steeringQueue: const []);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('steer-queue-item-0')), findsNothing);
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
    });

    testWidgets('keyboard only: Tab reaches the field during a run, and Enter steers', (tester) async {
      final session = _RecordingSession(
        's_min_test',
        const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.working,
          streamingTextBlocks: {0: 'Generating answer...'},
        ),
      );
      final settings = ComposerSettingsNotifier()..setSendWithEnter(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionStateFamily('s_min_test').overrideWith((ref) => session),
            composerSettingsProvider.overrideWith((ref) => settings),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: Composer(sessionId: 's_min_test')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('composer-text-field'));
      bool hasFocus() => tester.widget<TextField>(field).focusNode!.hasFocus;
      for (var i = 0; i < 12 && !hasFocus(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(hasFocus(), isTrue, reason: 'Tab must reach the field while Pi runs');

      await tester.enterText(field, 'cambia approccio');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.sent, ['cambia approccio']);
      expect(session.behaviors, ['steer']);
    });

    testWidgets('hides and restores unsent draft while an agent question is pending', (tester) async {
      const draft = 'Keep this unfinished message';
      final notifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.working,
          streamingTextBlocks: {0: 'Waiting for an answer...'},
        );
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('s_min_test').overrideWith((ref) => notifier),
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
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final composerField = find.byKey(const ValueKey('composer-text-field'));
      await tester.tap(composerField);
      await tester.pumpAndSettle();
      await tester.enterText(composerField, draft);
      await tester.pump();
      expect(container.read(composerDraftProvider('s_min_test')), draft);

      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.awaitingUser,
        streamingTextBlocks: const {},
        pendingUiRequests: const [
          {
            'requestId': 'question-1',
            'method': 'select',
            'dialog': true,
            'title': 'Choose an option',
            'options': ['Yes', 'No'],
          },
        ],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-extension-ui-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-input-area')), findsNothing);
      expect(composerField, findsNothing);
      expect(find.byKey(const ValueKey('composer-send-btn')), findsNothing);
      tester.testTextInput.enterText('This must not replace the draft');
      await tester.pump();
      expect(container.read(composerDraftProvider('s_min_test')), draft);

      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.working,
        pendingUiRequests: const [],
        streamingTextBlocks: const {0: 'Continuing after the answer...'},
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(tester.widget<TextField>(composerField).controller!.text, draft);
      expect(container.read(composerDraftProvider('s_min_test')), draft);
    });

    testWidgets('status line interrupt uses signalDanger colour', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      final interruptIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('composer-status-interrupt')),
          matching: find.byIcon(Icons.stop_rounded),
        ),
      );
      final interruptText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('composer-status-interrupt')),
          matching: find.text('Interrompi'),
        ),
      );

      expect(interruptIcon.color, FrameTokens.dark.signalDanger);
      expect(interruptText.style?.color, FrameTokens.dark.signalDanger);
    });

    testWidgets('keeps typed text in the field while the agent runs, even after focus is lost', (tester) async {
      final sessionNotifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_min_test').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('composer-text-field')), 'I have written some instructions here');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer while text was entered...'},
      );
      await tester.pump(const Duration(milliseconds: 1000));

      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-status-line')), findsOneWidget);
      expect(find.text('I have written some instructions here'), findsOneWidget);
    });

    testWidgets('transcript stays pinned to the bottom as the status line appears and leaves', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final entries = List.generate(
        30,
        (i) => SessionEntry(
          id: 'e_$i',
          role: i.isEven ? 'user' : 'assistant',
          text: 'Message $i with extra content lines to fill height\nLine 2\nLine 3',
          timestamp: 1000 + i,
        ),
      );

      final sessionNotifier = SessionStateNotifier('s_sync', null)
        ..state = SessionState(
          sessionId: 's_sync',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
          entries: entries,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionStateFamily('s_sync').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: TranscriptView(sessionId: 's_sync')),
                  Composer(sessionId: 's_sync'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollController = tester.widget<ListView>(find.byKey(const ValueKey('transcript-scroll'))).controller!;
      expect((scrollController.position.maxScrollExtent - scrollController.offset).abs(), lessThan(5.0));

      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Thinking...'},
      );
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(const ValueKey('composer-status-line')), findsOneWidget);
      await tester.pumpAndSettle();
      expect((scrollController.position.maxScrollExtent - scrollController.offset).abs(), lessThan(5.0));
    });
  });
}

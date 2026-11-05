import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/composer/composer_settings.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/file_mention_menu.dart';
import 'package:pi_frame/features/settings/settings_view.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _FakeComposerSession extends SessionStateNotifier {
  final List<String> sentPrompts = [];
  final List<String?> sentStreamingBehaviors = [];

  _FakeComposerSession({
    String sessionId = 'test-session',
    bool isStreaming = false,
  }) : super(sessionId, null) {
    state = SessionState(
      sessionId: sessionId,
      sessionName: 'Test Session',
      cwd: '/test/repo',
      agentStatus: isStreaming ? AgentStatus.working : AgentStatus.idle,
      entries: const [],
    );
  }

  @override
  Future<void> sendPrompt(String text, {String? streamingBehavior}) async {
    sentPrompts.add(text);
    sentStreamingBehaviors.add(streamingBehavior);
  }
}

class _FakeRepoController extends RepositoryController {
  _FakeRepoController() : super('test-session', () => null) {
    state = const RepositoryState(
      files: [
        {'path': 'lib/main.dart', 'sizeBytes': 1024},
        {'path': 'lib/app.dart', 'sizeBytes': 2048},
      ],
    );
  }
}

Widget _wrapComposer({
  required _FakeComposerSession session,
  required ComposerSettingsNotifier settingsNotifier,
  RepositoryController? repoController,
}) {
  return ProviderScope(
    overrides: [
      daemonEndpointProvider.overrideWith((ref) async => null),
      activeSessionIdProvider.overrideWith((ref) => session.sessionId),
      sessionStateFamily(session.sessionId).overrideWith((ref) => session),
      composerSettingsProvider.overrideWith((ref) => settingsNotifier),
      if (repoController != null)
        repositoryStateProvider(session.sessionId).overrideWith((ref) => repoController),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
      home: Scaffold(
        body: Composer(sessionId: session.sessionId),
      ),
    ),
  );
}

void main() {
  group('Composer keyboard send behavior', () {
    testWidgets('mode OFF: Enter inserts newline & no send, Ctrl+Enter sends', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(false);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Line 1');
      await tester.pumpAndSettle();

      // Enter in mode OFF should not send prompt (returns ignored to let TextField handle natively)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(session.sentPrompts, isEmpty);
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, 'Line 1');

      // Ctrl+Enter in mode OFF should send prompt
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(session.sentPrompts.length, 1);
      expect(session.sentPrompts.first, contains('Line 1'));
    });

    testWidgets('mode ON: Enter sends, Shift+Enter newline no send, NumpadEnter sends', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(true);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'First line');
      await tester.pumpAndSettle();

      // Shift+Enter in mode ON inserts newline and does not send
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(session.sentPrompts, isEmpty);
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, 'First line\n');

      // Enter in mode ON sends prompt
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(session.sentPrompts.length, 1);
      expect(session.sentPrompts.first, 'First line');

      // Prepare second message and send with NumpadEnter
      await tester.enterText(textFieldFinder, 'Second line');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();

      expect(session.sentPrompts.length, 2);
      expect(session.sentPrompts[1], 'Second line');
    });

    testWidgets('IME: with composing range valid, Enter does not send in BOTH modes', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();

      // Mode OFF
      settingsNotifier.setSendWithEnter(false);
      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      final controller = tester.widget<TextField>(textFieldFinder).controller!;

      // Active IME composition
      controller.value = const TextEditingValue(
        text: 'nih',
        composing: TextRange(start: 0, end: 3),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.sentPrompts, isEmpty);

      // Mode ON
      settingsNotifier.setSendWithEnter(true);
      await tester.pumpAndSettle();

      controller.value = const TextEditingValue(
        text: 'nihao',
        composing: TextRange(start: 0, end: 5),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.sentPrompts, isEmpty);

      // NumpadEnter during IME composition also does not send
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(session.sentPrompts, isEmpty);

      // Clear composition range -> now Enter sends
      controller.value = const TextEditingValue(
        text: 'nihao',
        selection: TextSelection.collapsed(offset: 5),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.sentPrompts.length, 1);
      expect(session.sentPrompts.first, 'nihao');
    });

    testWidgets('mention menu open + mode ON: Enter completes mention, does not send', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(true);
      final repo = _FakeRepoController();

      await tester.pumpWidget(
        _wrapComposer(
          session: session,
          settingsNotifier: settingsNotifier,
          repoController: repo,
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Please check @lib');
      await tester.pumpAndSettle();

      expect(find.byType(FileMentionMenu), findsOneWidget);

      // Press Enter to complete mention
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Mention should be completed and closed, NO prompt sent
      expect(session.sentPrompts, isEmpty);
      expect(find.byType(FileMentionMenu), findsNothing);
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, contains('@lib/main.dart'));
    });

    testWidgets('tooltips reflect active sendWithEnter mode', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(false);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      // Mode OFF tooltip
      expect(find.byTooltip('Invia prompt (Ctrl+Invio)'), findsOneWidget);

      // Mode ON tooltip
      settingsNotifier.setSendWithEnter(true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Invia prompt (Invio)'), findsOneWidget);
    });

    testWidgets('streaming steer behavior: mode ON Enter steers, mode OFF Ctrl+Enter steers', (tester) async {
      final streamingSession = _FakeComposerSession(isStreaming: true);
      final settingsNotifier = ComposerSettingsNotifier();

      // Mode OFF: Ctrl+Enter steers
      settingsNotifier.setSendWithEnter(false);
      await tester.pumpWidget(
        _wrapComposer(session: streamingSession, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      // Tap minimized bar to expand while streaming
      await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Steer prompt off');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(streamingSession.sentPrompts.length, 1);
      expect(streamingSession.sentPrompts.first, 'Steer prompt off');
      expect(streamingSession.sentStreamingBehaviors.first, 'steer');

      // Mode ON: Enter steers
      settingsNotifier.setSendWithEnter(true);
      await tester.pumpAndSettle();

      await tester.enterText(textFieldFinder, 'Steer prompt on');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(streamingSession.sentPrompts.length, 2);
      expect(streamingSession.sentStreamingBehaviors.length, 2);
      expect(streamingSession.sentPrompts[1], 'Steer prompt on');
      expect(streamingSession.sentStreamingBehaviors[1], 'steer');
    });

    testWidgets('mode ON: holding Enter (KeyDown + KeyRepeat(s) + KeyUp) sends exactly once and composer text is empty afterwards', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(true);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Held message');
      await tester.pumpAndSettle();

      // Simulate holding Enter: KeyDown + multiple KeyRepeat + KeyUp
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(session.sentPrompts.length, 1);
      expect(session.sentPrompts.first, 'Held message');
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, isEmpty);
    });

    testWidgets('mode ON: holding NumpadEnter sends exactly once and composer text is empty afterwards', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(true);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Numpad held message');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();

      expect(session.sentPrompts.length, 1);
      expect(session.sentPrompts.first, 'Numpad held message');
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, isEmpty);
    });

    testWidgets('mode OFF: holding Enter (KeyDown + KeyRepeat(s) + KeyUp) never sends', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(false);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Draft message');
      await tester.pumpAndSettle();

      // Simulate holding Enter in mode OFF: KeyDown + multiple KeyRepeat + KeyUp
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // In mode OFF, Enter repeats return ignored so TextField inserts newlines natively and prompt is NEVER sent
      expect(session.sentPrompts, isEmpty);
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, 'Draft message');
    });

    testWidgets('mode OFF: holding Ctrl+Enter sends exactly once', (tester) async {
      final session = _FakeComposerSession();
      final settingsNotifier = ComposerSettingsNotifier();
      settingsNotifier.setSendWithEnter(false);

      await tester.pumpWidget(
        _wrapComposer(session: session, settingsNotifier: settingsNotifier),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'Ctrl message');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(session.sentPrompts.length, 1);
      expect(session.sentPrompts.first, 'Ctrl message');
      final controller = tester.widget<TextField>(textFieldFinder).controller!;
      expect(controller.text, isEmpty);
    });

    testWidgets('multiline TextField proof: does not insert newline natively for Shift+Enter', (tester) async {
      final controller = TextEditingController(text: 'Initial text');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              maxLines: 5,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      // Proves multiline TextField in Flutter ignores Shift+Enter natively, justifying manual insertion
      expect(controller.text, 'Initial text');
    });
  });

  group('SettingsView composer toggle', () {
    testWidgets('settings toggle in settings view flips provider', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = ThemeRepository();
      addTearDown(repository.dispose);

      final settingsNotifier = ComposerSettingsNotifier();
      expect(settingsNotifier.state.sendWithEnter, isFalse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            themeRepositoryProvider.overrideWithValue(repository),
            composerSettingsProvider.overrideWith((ref) => settingsNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: Scaffold(
              body: SettingsView(
                initialTabIndex: 3, // Tab 4: Aspetto
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-composer-send-with-enter-switch'),
      );
      await tester.scrollUntilVisible(
        switchFinder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(switchFinder, findsOneWidget);

      // Tap toggle to enable
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsNotifier.state.sendWithEnter, isTrue);

      // Tap toggle again to disable
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(settingsNotifier.state.sendWithEnter, isFalse);
    });
  });
}

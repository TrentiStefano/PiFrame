import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_review_button.dart';
import 'package:pi_frame/features/composer/thinking_level_bars.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _host(String sessionId, SessionState state, {double width = 900}) {
  return ProviderScope(
    overrides: [
      daemonEndpointProvider.overrideWith((ref) async => null),
      sessionStateFamily(sessionId).overrideWith((ref) => SessionStateNotifier(sessionId, null)..state = state),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 300,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Composer(sessionId: sessionId),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Thinking level bars (plan 4.4)', () {
    test('each level lights a fixed number of the four bars', () {
      expect(thinkingLevelSteps('off'), 0);
      expect(thinkingLevelSteps('minimal'), 1);
      expect(thinkingLevelSteps('low'), 1);
      expect(thinkingLevelSteps('medium'), 2);
      expect(thinkingLevelSteps('high'), 3);
      expect(thinkingLevelSteps('xhigh'), 4);
      expect(thinkingLevelSteps('max'), 4);
      expect(thinkingLevelSteps(null), 2);
    });

    testWidgets('lit bars match the level', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: Scaffold(
            body: ThinkingLevelBars(level: 'high', litColor: FrameTokens.dark.thinking),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('thinking-bar-2-lit')), findsOneWidget);
      expect(find.byKey(const ValueKey('thinking-bar-3-dim')), findsOneWidget);
    });
  });

  group('Composer review button (plan 4.4)', () {
    testWidgets('with no changes the composer hides it', (tester) async {
      // Since c255a95 the composer shows the button only when Pi changed files
      // (or while a review is open), instead of a disabled placeholder.
      const sessionId = 'controls-no-changes';
      await tester.pumpWidget(_host(sessionId, const SessionState(sessionId: sessionId, cwd: '/fixture')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('review-changes-btn')), findsNothing);
    });

    testWidgets('a disabled button explains when it turns on', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: ComposerReviewButton(
              label: 'Rivedi modifiche',
              showLabel: true,
              reviewing: true,
              enabledTooltip: 'Chiudi revisione',
              disabledTooltip: 'Nessuna modifica da rivedere',
              onPressed: null,
            ),
          ),
        ),
      );

      final button = tester.widget<TextButton>(find.byKey(const ValueKey('review-changes-btn')));
      expect(button.onPressed, isNull);
      expect(find.byTooltip('Nessuna modifica da rivedere'), findsOneWidget);
    });

    testWidgets('label reads "Rivedi modifiche" without a count when there is nothing to review', (tester) async {
      // The label text itself is covered by strings_composer_test.dart; here the button is built directly.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: Scaffold(
            body: ComposerReviewButton(
              label: 'Rivedi modifiche',
              showLabel: true,
              reviewing: false,
              enabledTooltip: 'Rivedi modifiche ai file',
              disabledTooltip: 'Nessuna modifica',
              onPressed: null,
            ),
          ),
        ),
      );
      expect(find.text('Rivedi modifiche'), findsOneWidget);
    });
  });
}

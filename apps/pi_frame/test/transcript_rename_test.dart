import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('double-clicking session name enters rename mode and updates name', (
    tester,
  ) async {
    final notifier = SessionStateNotifier('session_1', null)
      ..state = SessionState(
        sessionId: 'session_1',
        sessionName: 'Old Title',
        cwd: '/test/repo',
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('session_1').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'session_1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial title is rendered
    expect(find.text('Old Title'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-name-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-name-rename-field')), findsNothing);

    // Double tap the title
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pumpAndSettle();

    // Verify rename field appears with current title
    expect(find.byKey(const ValueKey('session-name-rename-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-name-rename-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-name-rename-cancel')), findsOneWidget);

    // Enter new name and tap submit
    await tester.enterText(
      find.byKey(const ValueKey('session-name-rename-field')),
      'New Awesome Title',
    );
    await tester.tap(find.byKey(const ValueKey('session-name-rename-submit')));
    await tester.pumpAndSettle();

    // Verify editing closed and new name is reflected
    expect(find.byKey(const ValueKey('session-name-rename-field')), findsNothing);
    expect(find.text('New Awesome Title'), findsOneWidget);
    expect(notifier.state.sessionName, 'New Awesome Title');
  });

  testWidgets('pressing Enter on rename field submits and updates name', (
    tester,
  ) async {
    final notifier = SessionStateNotifier('session_enter', null)
      ..state = SessionState(
        sessionId: 'session_enter',
        sessionName: 'Old Title',
        cwd: '/test/repo',
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('session_enter').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'session_enter')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Double tap the title
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-name-rename-field')), findsOneWidget);

    // Enter new name
    await tester.enterText(
      find.byKey(const ValueKey('session-name-rename-field')),
      'Renamed Via Physical Enter',
    );
    await tester.pump();

    // Send Enter key
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-name-rename-field')), findsNothing);
    expect(find.text('Renamed Via Physical Enter'), findsOneWidget);
    expect(notifier.state.sessionName, 'Renamed Via Physical Enter');
  });

  testWidgets('pressing Numpad Enter on rename field submits and updates name', (
    tester,
  ) async {
    final notifier = SessionStateNotifier('session_numpad', null)
      ..state = SessionState(
        sessionId: 'session_numpad',
        sessionName: 'Old Title',
        cwd: '/test/repo',
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('session_numpad').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'session_numpad')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('session-name-rename-field')),
      'Renamed Via Numpad Enter',
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-name-rename-field')), findsNothing);
    expect(find.text('Renamed Via Numpad Enter'), findsOneWidget);
    expect(notifier.state.sessionName, 'Renamed Via Numpad Enter');
  });

  testWidgets('cancelling rename reverts without changing name', (
    tester,
  ) async {
    final notifier = SessionStateNotifier('session_2', null)
      ..state = SessionState(
        sessionId: 'session_2',
        sessionName: 'Keep This Name',
        cwd: '/test/repo',
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('session_2').overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'session_2')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Double tap to edit
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('session-name-title')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-name-rename-field')), findsOneWidget);

    // Type something but press cancel button
    await tester.enterText(
      find.byKey(const ValueKey('session-name-rename-field')),
      'Discarded Edit',
    );
    await tester.tap(find.byKey(const ValueKey('session-name-rename-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('session-name-rename-field')), findsNothing);
    expect(find.text('Keep This Name'), findsOneWidget);
    expect(notifier.state.sessionName, 'Keep This Name');
  });
}

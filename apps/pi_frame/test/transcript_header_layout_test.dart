import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame/ui/frame_middle_ellipsis.dart';
import 'package:pi_frame/ui/frame_pane_header.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _longCwd =
    r'C:\Users\user\.piframe-harness\integ\fixtures\workspace-with-a-very-long-folder-name\nested-subdirectory\submodule-repo-name-extra-long-path';

/// Pumps the real session header inside a box of [width] px and returns once
/// it has settled.
Future<void> _pumpHeader(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width + 200, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final notifier = SessionStateNotifier('header_layout', null)
    ..state = const SessionState(
      sessionId: 'header_layout',
      sessionName: 'Workspace planning',
      cwd: _longCwd,
      agentStatus: AgentStatus.settled,
      entries: [],
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        sessionStateFamily('header_layout').overrideWith((ref) => notifier),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 200,
              child: const TranscriptView(sessionId: 'header_layout'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The cwd subtitle of the session header: the middle-ellipsized path under
/// the title, found through the header that holds the status tag.
Finder _headerCwd() {
  final header = find.ancestor(
    of: find.byKey(const ValueKey('session-header-status')),
    matching: find.byType(FramePaneHeader),
  );
  return find.descendant(of: header, matching: find.byType(FrameMiddleEllipsis));
}

void main() {
  for (final width in [280.0, 320.0, 480.0, 800.0, 1200.0]) {
    testWidgets('session header status tag and cards sit on top row, cwd sits on line below at  px', (tester) async {
      await _pumpHeader(tester, width);

      final statusRect = tester.getRect(find.byKey(const ValueKey('session-header-status')));
      final titleRect = tester.getRect(find.byKey(const ValueKey('session-name-title')));
      final cwdRect = tester.getRect(_headerCwd());

      // Title and status badge do not overlap
      expect(titleRect.overlaps(statusRect), isFalse, reason: 'title  overlaps status ');
      // Cwd sits on a line below the title / status cards
      expect(cwdRect.top >= titleRect.bottom - 1.0, isTrue, reason: 'cwd  is not below title ');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [480.0, 800.0, 1200.0]) {
    testWidgets('long cwd is middle-ellipsized and the status keeps its width at  px', (tester) async {
      await _pumpHeader(tester, width);

      final cwdText = tester.widget<Text>(find.descendant(of: _headerCwd(), matching: find.byType(Text)));
      // The cwd is truncated with an ellipsis rather than overflowing.
      expect(cwdText.data, contains('…'));

      final statusRect = tester.getRect(find.byKey(const ValueKey('session-header-status')));
      // The status keeps its intrinsic width (the label and dot fit).
      expect(statusRect.width > 100, isTrue, reason: 'status ');
    });
  }

  for (final width in [480.0, 800.0, 1200.0, 1584.0]) {
    testWidgets('status pill is on far right, chips sit on its left and never intersect at  px', (tester) async {
      await _pumpHeader(tester, width);

      final statusRect = tester.getRect(find.byKey(const ValueKey('session-header-status')));
      final firstChipFinder = find.byKey(const ValueKey('session-header-context-chip'));
      final chipViewportRect = tester.getRect(
        find.ancestor(of: firstChipFinder, matching: find.byType(SingleChildScrollView)).first,
      );

      // Status pill is to the right of the chips
      expect(statusRect.overlaps(chipViewportRect), isFalse, reason: 'status  overlaps chip viewport ');
      expect(
        statusRect.left >= chipViewportRect.right - 0.5,
        isTrue,
        reason: 'status  is not to the right of chip viewport ',
      );
      expect(tester.takeException(), isNull);
    });
  }
}

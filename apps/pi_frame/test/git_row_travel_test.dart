import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/git/git_changes_pane.dart';

/// Git status that flips a file between the Staged and Changes groups when it
/// is staged or unstaged, as the daemon does.
class _TravelClient extends PcpClient {
  _TravelClient() : super(port: 1, token: 'test');

  final Map<String, bool> stagedByPath = {'notes.txt': false};

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async => {
    'data': {
      'isRepository': true,
      'rootPath': '/repo',
      'branch': 'main',
      'files': [
        for (final entry in stagedByPath.entries)
          {
            'path': entry.key,
            'status': 'modified',
            'staged': entry.value,
            'unstaged': !entry.value,
          },
      ],
      'totalAdditions': 1,
      'totalDeletions': 0,
    },
  };

  @override
  Future<Map<String, dynamic>> workspaceGitAction(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    final paths = (payload['paths'] as List).cast<String>();
    if (payload['action'] == 'stage') {
      for (final path in paths) {
        stagedByPath[path] = true;
      }
    } else if (payload['action'] == 'unstage') {
      for (final path in paths) {
        stagedByPath[path] = false;
      }
    }
    return {
      'data': {'status': <String, dynamic>{}},
    };
  }

  @override
  Future<WorkspaceListBranchesResult> listBranches(String sessionId) async =>
      const WorkspaceListBranchesResult(branches: [], headShortSha: 'a1b2c3d');
}

void main() {
  const unstagedRow = ValueKey('git-row-unstaged-notes.txt');
  const stagedRow = ValueKey('git-row-staged-notes.txt');
  const leavingRow = ValueKey('git-row-leaving-unstaged-notes.txt');
  const stageButton = ValueKey('git-unstaged-toggle-notes.txt');

  Future<_TravelClient> pumpPane(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _TravelClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('session-a').overrideWith(
            (ref) => SessionStateNotifier(
              'session-a',
              null,
            )..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 900),
              disableAnimations: disableAnimations,
            ),
            child: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('a staged row travels from Changes to Staged (Spec F)', (
    tester,
  ) async {
    await pumpPane(tester);
    expect(find.byKey(unstagedRow), findsOneWidget);
    expect(find.byKey(stagedRow), findsNothing);

    await tester.tap(find.byKey(stageButton));
    // The refresh has landed: counts already show the new state, and the row
    // is still fading out of its old group.
    await tester.pump();
    expect(find.byKey(stagedRow), findsOneWidget);
    expect(find.byKey(leavingRow), findsOneWidget);
    expect(find.byKey(unstagedRow), findsNothing);

    // The arriving row starts transparent and rises into place.
    final arriveOpacity = tester.widget<Opacity>(
      find
          .descendant(of: find.byKey(stagedRow), matching: find.byType(Opacity))
          .first,
    );
    expect(arriveOpacity.opacity, lessThan(1));

    await tester.pumpAndSettle();
    expect(find.byKey(leavingRow), findsNothing);
    expect(find.byKey(stagedRow), findsOneWidget);
  });

  testWidgets('reduced motion moves the row at once (no leaving copy)', (
    tester,
  ) async {
    await pumpPane(tester, disableAnimations: true);
    await tester.tap(find.byKey(stageButton));
    await tester.pump();
    expect(find.byKey(stagedRow), findsOneWidget);
    expect(find.byKey(leavingRow), findsNothing);
    final arriveOpacity = tester.widget<Opacity>(
      find
          .descendant(of: find.byKey(stagedRow), matching: find.byType(Opacity))
          .first,
    );
    expect(arriveOpacity.opacity, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('Shift+F10 on the cursor Git row opens its row menu', (
    tester,
  ) async {
    await pumpPane(tester);
    // The list is the one Tab stop: give it focus, then move the cursor from
    // the Staged header (empty) down past the Changes header onto notes.txt.
    tester
        .widget<Focus>(
          find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.debugLabel == 'git-list',
          ),
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<String>), findsWidgets);
  });
}

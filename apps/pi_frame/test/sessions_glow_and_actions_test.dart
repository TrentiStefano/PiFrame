import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/removed_repos_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame/ui/frame_list_row.dart';
import 'package:pi_frame/ui/shimmer_border.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(super.initial);
}

class _TestRemovedNotifier extends RemovedReposNotifier {
  _TestRemovedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

void main() {
  testWidgets(
    'working border and spinner clear after the answer, and the notification dot lights until the session is opened',
    (tester) async {
      final mockSessions = [
        {
          'id': 'sess_active_1',
          'name': 'Open Idle Session',
          'cwd': 'C:/projects/myrepo',
          'isActive': true, // Technically open session
          'lastMessagePreview': 'Answer given',
        },
      ];

      final sessionNotifier = SessionStateNotifier('sess_active_1', null)
        ..state = SessionState(
          sessionId: 'sess_active_1',
          sessionName: 'Open Idle Session',
          cwd: 'C:/projects/myrepo',
          agentStatus: AgentStatus.settled, // Idle / answer given
          entries: [],
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
            pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
            removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
            activeSessionIdProvider.overrideWith((ref) => null),
            sessionStateFamily('sess_active_1').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(body: SessionsSidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Folder "myrepo" exists and, as the only repository, is expanded by default
      expect(find.text('myrepo'), findsOneWidget);
      expect(find.text('Open Idle Session'), findsOneWidget);

      bool hasWorkingBorder() {
        final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
        return boxes.any((b) {
          final dec = b.decoration;
          if (dec is BoxDecoration && dec.border != null) {
            return dec.border!.top.color == FrameTokens.dark.agentWorking.withValues(alpha: 0.7);
          }
          return false;
        });
      }

      final darkDot = find.byKey(const ValueKey('session-unread-dot-sess_active_1-false'));
      final litDot = find.byKey(const ValueKey('session-unread-dot-sess_active_1-true'));
      final spinner = find.byKey(const ValueKey('session-working-spinner'));

      // Idle with nothing new: no working border, and the dot is dark.
      expect(hasWorkingBorder(), isFalse);
      expect(find.byType(ShimmerBorder), findsNothing, reason: 'Cards in Sessions tab must not shimmer');
      expect(darkDot, findsOneWidget);
      expect(litDot, findsNothing);
      expect(find.byKey(const ValueKey('folder-unread-dot:C:/projects/myrepo')), findsNothing);

      // The agent works: spinner and working border, no shimmer.
      sessionNotifier.state = sessionNotifier.state.copyWith(agentStatus: AgentStatus.working);
      await tester.pump();
      expect(hasWorkingBorder(), isTrue);
      expect(spinner, findsOneWidget);
      expect(find.byType(ShimmerBorder), findsNothing, reason: 'Cards in Sessions tab must not shimmer');

      // It answers while another session is open: the dot lights up.
      sessionNotifier.state = sessionNotifier.state.copyWith(agentStatus: AgentStatus.settled);
      await tester.pumpAndSettle();
      expect(hasWorkingBorder(), isFalse);
      expect(spinner, findsNothing);
      expect(litDot, findsOneWidget);
      expect(find.byKey(const ValueKey('folder-unread-dot:C:/projects/myrepo')), findsOneWidget);

      // Opening the session marks it read.
      final container = ProviderScope.containerOf(tester.element(find.byType(SessionsSidebar)));
      container.read(activeSessionIdProvider.notifier).state = 'sess_active_1';
      await tester.pumpAndSettle();
      expect(litDot, findsNothing);
      expect(darkDot, findsOneWidget);
    },
  );

  testWidgets('a session left mid-run keeps its spinner and lights its dot when the answer lands', (tester) async {
    final mockSessions = [
      {'id': 'run', 'name': 'Running Session', 'cwd': 'C:/projects/myrepo'},
      {'id': 'other', 'name': 'Other Session', 'cwd': 'C:/projects/myrepo'},
    ];
    final running = SessionStateNotifier(
      'run',
      null,
    )..state = SessionState(sessionId: 'run', cwd: 'C:/projects/myrepo', agentStatus: AgentStatus.working, entries: []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
          activeSessionIdProvider.overrideWith((ref) => 'run'),
          sessionStateFamily('run').overrideWith((ref) => running),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SessionsSidebar)));

    final folderName = find.text('myrepo');
    final nameX = tester.getTopLeft(folderName).dx;

    // Switch away while it still works: the row keeps its live spinner, the
    // folder keeps its working dot, and the folder name does not move.
    container.read(activeSessionIdProvider.notifier).state = 'other';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-working-spinner')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-working-dot:C:/projects/myrepo')), findsOneWidget);
    expect(tester.getTopLeft(folderName).dx, nameX);

    // The working border is painted over the row, so a selected or
    // hovered row's opaque fill cannot hide it.
    final border = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const ValueKey('session-tile-C:/projects/myrepo-run')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .firstWhere((box) {
          final dec = box.decoration;
          return dec is BoxDecoration && dec.border?.top.color == FrameTokens.dark.agentWorking.withValues(alpha: 0.7);
        });
    expect(border.position, DecorationPosition.foreground);

    running.state = running.state.copyWith(agentStatus: AgentStatus.settled);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-working-spinner')), findsNothing);
    expect(find.byKey(const ValueKey('session-unread-dot-run-true')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-unread-dot-other-false')), findsOneWidget);
    expect(tester.getTopLeft(folderName).dx, nameX, reason: 'the folder name stays put when work stops');
  });

  testWidgets('working folder indicator stays static while the session row shows a spinner', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_working',
        'name': 'Working Session',
        'cwd': 'C:/projects/myrepo',
        'isActive': true,
        'status': 'working',
      },
    ];
    final sessionNotifier = SessionStateNotifier('sess_working', null)
      ..state = SessionState(
        sessionId: 'sess_working',
        sessionName: 'Working Session',
        cwd: 'C:/projects/myrepo',
        agentStatus: AgentStatus.working,
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
          activeSessionIdProvider.overrideWith((ref) => null),
          sessionStateFamily('sess_working').overrideWith((ref) => sessionNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final folder = find.byKey(const ValueKey('session-folder:C:/projects/myrepo'));
    final folderDot = find.byKey(const ValueKey('folder-working-dot:C:/projects/myrepo'));
    expect(folder, findsOneWidget);
    expect(folderDot, findsOneWidget);
    expect(find.descendant(of: folder, matching: find.byType(AnimatedBuilder)), findsNothing);
    expect((tester.widget<Container>(folderDot).decoration! as BoxDecoration).boxShadow, isNull);

    // The only repository is the active one, so it is expanded by default.
    final sessionTile = find.ancestor(of: find.text('Working Session'), matching: find.byType(FrameListRow));
    expect(
      find.descendant(of: sessionTile, matching: find.byKey(const ValueKey('session-working-spinner'))),
      findsOneWidget,
    );
  });

  testWidgets('rail surface has no box shadows and the folder new-session target is 28 px', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_working',
        'name': 'Working Session',
        'cwd': 'C:/projects/myrepo',
        'isActive': true,
        'status': 'working',
      },
    ];
    final sessionNotifier = SessionStateNotifier('sess_working', null)
      ..state = SessionState(
        sessionId: 'sess_working',
        sessionName: 'Working Session',
        cwd: 'C:/projects/myrepo',
        agentStatus: AgentStatus.working,
        entries: [],
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
          activeSessionIdProvider.overrideWith((ref) => null),
          sessionStateFamily('sess_working').overrideWith((ref) => sessionNotifier),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flat surface: no decoration in the rail carries a shadow, glow included.
    final shadowed = tester
        .widgetList<Container>(find.descendant(of: find.byType(SessionsSidebar), matching: find.byType(Container)))
        .where(
          (c) => c.decoration is BoxDecoration && ((c.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false),
        );
    expect(shadowed, isEmpty);

    // The per-folder new-session button meets the 28 px minimum target.
    final newInFolder = find.byKey(const ValueKey('repo-new-session-btn-C:/projects/myrepo'));
    expect(newInFolder, findsOneWidget);
    expect(tester.getSize(newInFolder), const Size.square(FrameSize.hitMin));
  });

  testWidgets('repo remove button opens dialog with hide and delete all options', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_repo_1',
        'name': 'Test Session',
        'cwd': 'C:/projects/demo_repo',
        'isActive': false,
        'lastMessagePreview': 'Hello',
      },
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
          activeSessionIdProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Right-click on folder tile to open context menu
    await tester.tap(find.text('demo_repo'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    final removeRepoItem = find.text('Remove repository from sidebar');
    expect(removeRepoItem, findsOneWidget);

    await tester.tap(removeRepoItem);
    await tester.pumpAndSettle();

    // Dialog should appear with removal options
    expect(find.text('Remove repository "demo_repo"'), findsOneWidget);
    expect(find.text('Remove from view only'), findsOneWidget);
    expect(find.text('Delete repository and all sessions...'), findsOneWidget);

    // Tap on "Delete repository and all sessions..." to test the double confirmation
    await tester.tap(find.byKey(const ValueKey('delete-all-repo-sessions-btn')));
    await tester.pumpAndSettle();

    // Second warning dialog with required "delete" box
    expect(find.text('WARNING: Deletion'), findsOneWidget);
    final deleteField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'delete');
    expect(deleteField, findsOneWidget);

    // Initially confirm button is disabled
    final confirmBtn = find.widgetWithText(FilledButton, 'Delete all');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

    // Type "delete" in input box
    await tester.enterText(deleteField, 'delete');
    await tester.pumpAndSettle();

    // Confirm button is now enabled
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
  });

  testWidgets('session context menu on right click shows repository and session options', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_repo_1',
        'name': 'Test Session',
        'cwd': 'C:/projects/demo_repo',
        'isActive': false,
        'lastMessagePreview': 'Hello',
      },
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
          activeSessionIdProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The only repository is expanded by default, so the session is visible.
    // Right-click on session tile
    await tester.tap(find.text('Test Session'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    // Session menu holds session actions only; repository actions moved to the repository row.
    expect(find.text('Delete session'), findsOneWidget);
    expect(find.text('Repository instructions'), findsNothing);
    expect(find.text('Remove repository from sidebar'), findsNothing);
  });

  testWidgets('delete session with confirmation popup works correctly', (tester) async {
    final mockSessions = [
      {
        'id': 'sess_to_delete',
        'name': 'Session To Delete',
        'cwd': 'C:/projects/demo_repo',
        'isActive': false,
        'lastMessagePreview': 'Goodbye',
      },
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) => Future.value(mockSessions)),
          pinnedSessionsProvider.overrideWith((ref) => _TestPinnedNotifier({})),
          removedReposProvider.overrideWith((ref) => _TestRemovedNotifier({})),
          activeSessionIdProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: SessionsSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The only repository is expanded by default
    expect(find.text('Session To Delete'), findsOneWidget);

    // The row's menu button is revealed on hover only; right-click opens the same menu.
    await tester.tap(find.byKey(const ValueKey('session-row-sess_to_delete')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    // Click "Delete session" in menu
    expect(find.text('Delete session'), findsOneWidget);
    await tester.tap(find.text('Delete session'));
    await tester.pumpAndSettle();

    // Confirmation dialog must appear
    expect(find.text('Delete session'), findsOneWidget);
    expect(find.textContaining('Are you sure you want to delete session'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

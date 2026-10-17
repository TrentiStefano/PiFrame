import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_crust/features/sessions_sidebar/removed_repos_provider.dart';
import 'package:pi_crust/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_crust/ui/shimmer_border.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class _TestPinnedNotifier extends PinnedSessionsNotifier {
  _TestPinnedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

class _TestRemovedNotifier extends RemovedReposNotifier {
  _TestRemovedNotifier(Set<String> initial) : super() {
    state = initial;
  }
}

void main() {
  testWidgets(
    'glowing shimmer disappears after answer while active semaphore dot remains visible',
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
            sessionListProvider.overrideWith(
              (ref) => Future.value(mockSessions),
            ),
            pinnedSessionsProvider.overrideWith(
              (ref) => _TestPinnedNotifier({}),
            ),
            removedReposProvider.overrideWith(
              (ref) => _TestRemovedNotifier({}),
            ),
            activeSessionIdProvider.overrideWith((ref) => null),
            sessionStateFamily('sess_active_1').overrideWith(
              (ref) => sessionNotifier,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [CrustTokens.dark],
            ),
            home: const Scaffold(body: SessionsSidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Folder "myrepo" exists
      expect(find.text('myrepo'), findsOneWidget);

      // Tap on folder "myrepo" to expand it
      await tester.tap(find.text('myrepo'));
      await tester.pumpAndSettle();

      expect(find.text('Open Idle Session'), findsOneWidget);

      // Verify that NO ShimmerBorder is actively glowing when session is settled
      final idleShimmers = tester.widgetList<ShimmerBorder>(
        find.byType(ShimmerBorder),
      );
      expect(
        idleShimmers.any((s) => s.isActive),
        isFalse,
        reason: 'Idle open session should not glow',
      );

      // Verify that active semaphore dot IS present
      final activeDots = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 6 &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(activeDots, findsWidgets, reason: 'Active dot should be visible');

      // Now simulate agent generating (working)
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
      );
      await tester.pump();

      // Now glowing shimmer should be active
      final workingShimmers = tester.widgetList<ShimmerBorder>(
        find.byType(ShimmerBorder),
      );
      expect(
        workingShimmers.any((s) => s.isActive),
        isTrue,
        reason: 'Working session must glow',
      );

      // Agent finishes generating and transitions back to settled
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.settled,
      );
      await tester.pump();

      // Glowing shimmer disappears
      final settledShimmers = tester.widgetList<ShimmerBorder>(
        find.byType(ShimmerBorder),
      );
      expect(
        settledShimmers.any((s) => s.isActive),
        isFalse,
        reason: 'Glow must disappear when agent finished',
      );

      // Semaphore dot remains active
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 6 &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'repo remove button opens dialog with hide and delete all options',
    (tester) async {
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
            sessionListProvider.overrideWith(
              (ref) => Future.value(mockSessions),
            ),
            pinnedSessionsProvider.overrideWith(
              (ref) => _TestPinnedNotifier({}),
            ),
            removedReposProvider.overrideWith(
              (ref) => _TestRemovedNotifier({}),
            ),
            activeSessionIdProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [CrustTokens.dark],
            ),
            home: const Scaffold(body: SessionsSidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final removeRepoBtn = find.byTooltip('Rimuovi repository dal riquadro');
      expect(removeRepoBtn, findsOneWidget);

      await tester.tap(removeRepoBtn);
      await tester.pumpAndSettle();

      // Dialog should appear with removal options
      expect(find.text('Rimuovi repository "demo_repo"'), findsOneWidget);
      expect(find.text('Rimuovi solo dalla vista'), findsOneWidget);
      expect(
        find.text('Elimina repository e tutte le sessioni...'),
        findsOneWidget,
      );

      // Tap on "Elimina repository e tutte le sessioni..." to test the double confirmation
      await tester.tap(find.byKey(const ValueKey('delete-all-repo-sessions-btn')));
      await tester.pumpAndSettle();

      // Second warning dialog with required "delete" box
      expect(find.text('ATTENZIONE: Eliminazione'), findsOneWidget);
      final deleteField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'delete',
      );
      expect(deleteField, findsOneWidget);

      // Initially confirm button is disabled
      final confirmBtn = find.widgetWithText(FilledButton, 'Elimina tutto');
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

      // Type "delete" in input box
      await tester.enterText(deleteField, 'delete');
      await tester.pumpAndSettle();

      // Confirm button is now enabled
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
    },
  );

  testWidgets(
    'delete session with confirmation popup works correctly',
    (tester) async {
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
            sessionListProvider.overrideWith(
              (ref) => Future.value(mockSessions),
            ),
            pinnedSessionsProvider.overrideWith(
              (ref) => _TestPinnedNotifier({}),
            ),
            removedReposProvider.overrideWith(
              (ref) => _TestRemovedNotifier({}),
            ),
            activeSessionIdProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [CrustTokens.dark],
            ),
            home: const Scaffold(body: SessionsSidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand folder
      await tester.tap(find.text('demo_repo'));
      await tester.pumpAndSettle();

      expect(find.text('Session To Delete'), findsOneWidget);

      // Find PopupMenuButton on session tile
      final moreBtn = find.byTooltip('Azioni sessione');
      expect(moreBtn, findsOneWidget);

      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Click "Elimina sessione" in menu
      expect(find.text('Elimina sessione'), findsOneWidget);
      await tester.tap(find.text('Elimina sessione'));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.text('Elimina sessione'), findsOneWidget);
      expect(
        find.textContaining('Sei sicuro di voler eliminare la sessione'),
        findsOneWidget,
      );
      expect(find.text('Elimina'), findsOneWidget);
      expect(find.text('Annulla'), findsOneWidget);
    },
  );
}

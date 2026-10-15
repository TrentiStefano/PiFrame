import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/app/app_shell.dart';
import 'package:pi_crust/app/desktop_chrome.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/data/daemon/pcp_client.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/features/composer/composer.dart';
import 'package:pi_crust/features/session_changes/diff_parser.dart';
import 'package:pi_crust/features/session_changes/review_file_diff_viewer.dart';
import 'package:pi_crust/features/session_changes/session_changes_pane.dart';
import 'package:pi_crust/features/session_changes/session_changes_provider.dart';
import 'package:pi_crust/features/workspace/repository_workspace.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class _TestSessionChangesNotifier extends StateNotifier<SessionChangesState>
    implements SessionChangesNotifier {
  _TestSessionChangesNotifier(super.state);

  @override
  late final Ref ref;

  @override
  String get sessionId => 'session_1';

  @override
  Future<void> refresh() async {}

  @override
  Future<void> fetchFileDiff(String filePath) async {}
}

void main() {
  group('DiffParser tests', () {
    test('parses unified diff into hunks and lines', () {
      const sampleDiff = '''
diff --git a/packages/pcp-ts/src/types.ts b/packages/pcp-ts/src/types.ts
index ccb1dd3..d31323b 100644
--- a/packages/pcp-ts/src/types.ts
+++ b/packages/pcp-ts/src/types.ts
@@ -99,6 +99,7 @@ export type PcpCommandType =
   | 'session.attach'
   | 'session.detach'
   | 'session.closeWorker'
+  | 'session.delete'
   | 'session.rename'
   | 'session.fork'
   | 'session.clone'
''';

      final parsed = DiffParser.parse(sampleDiff);
      expect(parsed.hunks.length, 1);
      final hunk = parsed.hunks.first;
      expect(hunk.oldStart, 99);
      expect(hunk.newStart, 99);
      expect(hunk.lines.any((l) => l.type == DiffLineType.addition && l.text.contains('session.delete')), isTrue);

      final splitRows = hunk.toSplitRows();
      expect(splitRows.isNotEmpty, isTrue);
      final addedRow = splitRows.firstWhere((r) => r.right?.text.contains('session.delete') == true);
      expect(addedRow.left, isNull);
      expect(addedRow.right?.newLineNumber, 102);
    });
  });

  group('Review Changes UI tests', () {
    testWidgets(
      'Review changes button appears next to send button when agent finished and modified files',
      (tester) async {
        final mockSessionState = SessionState(
          sessionId: 'session_1',
          sessionName: 'Feature Session',
          cwd: 'C:/projects/demo',
          agentStatus: AgentStatus.settled, // Finished answering
          entries: const [
            SessionEntry(
              id: 'entry_1',
              role: 'assistant',
              text: 'Modified files.',
              timestamp: 123456,
              toolCalls: [
                ToolExecutionState(
                  toolCallId: 'tc_1',
                  toolName: 'write',
                  args: {'path': 'lib/main.dart'},
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              daemonEndpointProvider.overrideWith((ref) async => null),
              sessionStateFamily('session_1').overrideWith(
                (ref) => SessionStateNotifier('session_1', null)..state = mockSessionState,
              ),
              sessionChangesProvider('session_1').overrideWith(
                (ref) => SessionChangesNotifier(ref, 'session_1')
                  ..state = const SessionChangesState(
                    files: [
                      SessionChangedFile(
                        path: 'lib/main.dart',
                        filename: 'main.dart',
                        directory: 'lib',
                        additions: 12,
                        deletions: 2,
                      ),
                    ],
                  ),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [CrustTokens.dark],
              ),
              home: const Scaffold(
                body: Composer(sessionId: 'session_1'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The "Review changes" button should be visible on the left side of the "Invia" button
        final reviewBtnFinder = find.byKey(const ValueKey('review-changes-btn'));
        expect(reviewBtnFinder, findsOneWidget);
        expect(find.text('Review changes'), findsOneWidget);
        expect(find.text('Invia'), findsOneWidget);

        // Verify button position: Review changes button should be to the left of Invia
        final reviewCenter = tester.getCenter(reviewBtnFinder);
        final sendCenter = tester.getCenter(find.text('Invia'));
        expect(reviewCenter.dx, lessThan(sendCenter.dx));
      },
    );

    testWidgets(
      'SessionChangesPane renders file list with file badges, additions and deletions',
      (tester) async {
        const sampleDiff = '''
@@ -1,3 +1,4 @@
 line 1
-old line 2
+new line 2
 line 3
''';

        final notifier = _TestSessionChangesNotifier(
          const SessionChangesState(
            files: [
              SessionChangedFile(
                path: 'apps/agentd/src/sessions/SessionIndex.ts',
                filename: 'SessionIndex.ts',
                directory: 'apps/agentd/src/sessions',
                additions: 23,
                deletions: 0,
                diff: sampleDiff,
              ),
              SessionChangedFile(
                path: 'apps/pi_crust/lib/data/daemon/pcp_client.dart',
                filename: 'pcp_client.dart',
                directory: 'apps/pi_crust/lib/data/daemon',
                additions: 13,
                deletions: 1,
                diff: sampleDiff,
              ),
            ],
            totalAdditions: 36,
            totalDeletions: 1,
          ),
        );

        bool closed = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionChangesProvider('session_1').overrideWith((ref) => notifier),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [CrustTokens.dark],
              ),
              home: Scaffold(
                body: SessionChangesPane(
                  sessionId: 'session_1',
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Title and count
        expect(find.text('Review Changes'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        // Files listed
        expect(find.text('SessionIndex.ts'), findsOneWidget);
        expect(find.text('apps/agentd/src/sessions'), findsOneWidget);
        expect(find.text('+23'), findsOneWidget);
        expect(find.text('-0'), findsOneWidget);

        expect(find.text('pcp_client.dart'), findsOneWidget);
        expect(find.text('apps/pi_crust/lib/data/daemon'), findsOneWidget);
        expect(find.text('+13'), findsOneWidget);
        expect(find.text('-1'), findsOneWidget);

        // Click on SessionIndex.ts to expand diff
        await tester.tap(find.byKey(const ValueKey('review-file-apps/agentd/src/sessions/SessionIndex.ts')));
        await tester.pumpAndSettle();

        // Diff lines should now be displayed
        expect(find.byType(ReviewFileDiffViewer), findsOneWidget);
        expect(find.textContaining('new line 2'), findsOneWidget);

        // Toggle diff mode button
        final toggleModeBtn = find.byKey(const ValueKey('toggle-diff-mode-btn'));
        expect(toggleModeBtn, findsOneWidget);
        await tester.tap(toggleModeBtn);
        await tester.pumpAndSettle();

        // Close button
        final closeBtn = find.byKey(const ValueKey('close-session-changes-btn'));
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'AppShell layout switches to 50/50 split between Chat and SessionChangesPane with minimized sessions sidebar and hidden repo pane',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final container = ProviderContainer(
          overrides: [
            desktopWindowLifecycleProvider.overrideWithValue(false),
            desktopChromeProvider.overrideWithValue(false),
            activeSessionIdProvider.overrideWith((ref) => 'session_1'),
            connectionStateProvider.overrideWith(
              (ref) => Stream.value(DaemonConnectionState.connected),
            ),
            sessionStateFamily('session_1').overrideWith(
              (ref) => SessionStateNotifier('session_1', null)
                ..state = const SessionState(
                  sessionId: 'session_1',
                  cwd: 'C:/repo',
                ),
            ),
            repositoryStateProvider('session_1').overrideWith(
              (ref) => RepositoryController('session_1', () => null),
            ),
            sessionChangesProvider('session_1').overrideWith(
              (ref) => SessionChangesNotifier(ref, 'session_1')
                ..state = const SessionChangesState(
                  files: [
                    SessionChangedFile(
                      path: 'lib/foo.dart',
                      filename: 'foo.dart',
                      directory: 'lib',
                      additions: 5,
                      deletions: 1,
                    ),
                  ],
                ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [CrustTokens.dark],
              ),
              home: const AppShell(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially: Repository pane is visible, GitChangesPane is visible
        expect(find.byType(RepositoryPane), findsOneWidget);
        expect(find.byType(GitChangesPane), findsOneWidget);
        expect(find.byType(SessionChangesPane), findsNothing);

        // Activate Review Changes mode
        container.read(isReviewingChangesProvider.notifier).state = true;
        await tester.pumpAndSettle();

        // Now:
        // 1. Sessions sidebar is minimized (showing collapsed strip with 'SESSIONI')
        expect(find.text('SESSIONI'), findsOneWidget);
        // 2. Repository pane is hidden
        expect(find.byType(RepositoryPane), findsNothing);
        // 3. GitChangesPane is replaced by SessionChangesPane
        expect(find.byType(GitChangesPane), findsNothing);
        expect(find.byType(SessionChangesPane), findsOneWidget);

        // Close review changes mode
        container.read(isReviewingChangesProvider.notifier).state = false;
        await tester.pumpAndSettle();

        // Restored layout:
        expect(find.byType(RepositoryPane), findsOneWidget);
        expect(find.byType(GitChangesPane), findsOneWidget);
        expect(find.byType(SessionChangesPane), findsNothing);
      },
    );
  });
}

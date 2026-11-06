import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/branch_picker_dialog.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';

class _MockBranchClient extends PcpClient {
  _MockBranchClient() : super(port: 1, token: 'test');

  List<WorkspaceBranchInfo> mockBranches = [
    const WorkspaceBranchInfo(
      name: 'main',
      isCurrent: true,
      upstream: 'origin/main',
      ahead: 1,
      behind: 2,
      lastCommitUnix: 1700000000,
    ),
    const WorkspaceBranchInfo(
      name: 'feature/login',
      isCurrent: false,
      upstream: 'origin/feature/login',
      ahead: 0,
      behind: 0,
      lastCommitUnix: 1699900000,
    ),
    const WorkspaceBranchInfo(
      name: 'fix#12',
      isCurrent: false,
      lastCommitUnix: 1699800000,
    ),
    const WorkspaceBranchInfo(
      name: 'feature/ä-ü',
      isCurrent: false,
      lastCommitUnix: 1699700000,
    ),
    const WorkspaceBranchInfo(
      name: 'emoji-🚀',
      isCurrent: false,
      lastCommitUnix: 1699600000,
    ),
    const WorkspaceBranchInfo(
      name: 'quote"branch',
      isCurrent: false,
      lastCommitUnix: 1699500000,
    ),
  ];

  String currentBranch = 'main';
  bool detached = false;
  String? headShortSha = 'a1b2c3d';
  int refreshCount = 0;

  final switchCalls = <({String branch, String onDirty})>[];
  Object? switchErrorToThrow;
  WorkspaceSwitchBranchResult Function(String branch, String onDirty)?
      onSwitchBranch;

  @override
  Future<WorkspaceListBranchesResult> listBranches(String sessionId) async {
    return WorkspaceListBranchesResult(
      branches: mockBranches,
      currentBranch: currentBranch,
      detached: detached,
      headShortSha: headShortSha,
    );
  }

  @override
  Future<WorkspaceSwitchBranchResult> switchBranch(
    String sessionId,
    String branch, {
    String onDirty = 'block',
  }) async {
    switchCalls.add((branch: branch, onDirty: onDirty));
    if (switchErrorToThrow != null) {
      throw switchErrorToThrow!;
    }
    if (onSwitchBranch != null) {
      return onSwitchBranch!(branch, onDirty);
    }
    currentBranch = branch;
    return WorkspaceSwitchBranchResult(
      currentBranch: branch,
      stashed: false,
      stashMessage: null,
    );
  }

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async {
    refreshCount++;
    return {
      'data': {
        'isRepository': true,
        'rootPath': '/repo',
        'branch': detached ? null : currentBranch,
        'detached': detached,
        'headShortSha': headShortSha,
        'files': <Map<String, dynamic>>[],
        'totalAdditions': 0,
        'totalDeletions': 0,
      },
    };
  }
}

Widget _wrapWithApp({
  required Widget child,
  required PcpClient client,
  AppLanguage language = AppLanguage.en,
  AgentStatus agentStatus = AgentStatus.idle,
  bool readOnly = false,
}) {
  return ProviderScope(
    overrides: [
      pcpClientProvider.overrideWithValue(client),
      appLanguageProvider.overrideWith((ref) => AppLanguageNotifier()..setLanguage(language)),
      sessionStateFamily('session-a').overrideWith(
        (ref) => SessionStateNotifier('session-a', null)
          ..state = SessionState(
            sessionId: 'session-a',
            cwd: '/repo',
            agentStatus: agentStatus,
            readOnly: readOnly,
          ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: const [FrameTokens.light],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('BranchPickerDialog', () {
    testWidgets('picker lists branches with current highlighted', (tester) async {
      final client = _MockBranchClient();
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BranchPickerDialog.show(
                context,
                sessionId: 'session-a',
                client: client,
                currentBranch: 'main',
              ),
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check current branch is rendered with check icon and current badge
      expect(find.text('main'), findsOneWidget);
      expect(find.byKey(const ValueKey('branch-picker-current-check')), findsOneWidget);
      expect(find.text('Current branch'), findsOneWidget);

      // Other branches rendered
      expect(find.text('feature/login'), findsOneWidget);
      expect(find.text('origin/main'), findsOneWidget);
      expect(find.text('↑1 ↓2'), findsOneWidget);
    });

    testWidgets('search filters branches', (tester) async {
      final client = _MockBranchClient();
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BranchPickerDialog.show(
                context,
                sessionId: 'session-a',
                client: client,
                currentBranch: 'main',
              ),
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter query 'login'
      await tester.enterText(
        find.byKey(const ValueKey('branch-picker-search-field')),
        'login',
      );
      await tester.pumpAndSettle();

      expect(find.text('feature/login'), findsOneWidget);
      expect(find.text('main'), findsNothing);
      expect(find.text('fix#12'), findsNothing);
    });

    testWidgets('weird names render (unicode, "#", quotes)', (tester) async {
      final client = _MockBranchClient();
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BranchPickerDialog.show(
                context,
                sessionId: 'session-a',
                client: client,
                currentBranch: 'main',
              ),
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('feature/ä-ü'), findsOneWidget);
      expect(find.text('fix#12'), findsOneWidget);
      expect(find.text('emoji-🚀'), findsOneWidget);
      expect(find.text('quote"branch'), findsOneWidget);
    });

    testWidgets('selecting current branch just closes dialog without returning value', (tester) async {
      final client = _MockBranchClient();
      String? selected;
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selected = await BranchPickerDialog.show(
                  context,
                  sessionId: 'session-a',
                  client: client,
                  currentBranch: 'main',
                );
              },
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap on main (current branch)
      await tester.tap(find.byKey(const ValueKey('branch-picker-item-main')));
      await tester.pumpAndSettle();

      expect(find.byType(BranchPickerDialog), findsNothing);
      expect(selected, isNull);
    });

    testWidgets('keyboard navigation and Enter selects branch', (tester) async {
      final client = _MockBranchClient();
      String? selected;
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selected = await BranchPickerDialog.show(
                  context,
                  sessionId: 'session-a',
                  client: client,
                  currentBranch: 'main',
                );
              },
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Press down arrow to move from index 0 ('main') to index 1 ('feature/login')
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // Press Enter to select
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(BranchPickerDialog), findsNothing);
      expect(selected, 'feature/login');
    });

    testWidgets('Esc key closes picker', (tester) async {
      final client = _MockBranchClient();
      String? selected = 'initial';
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selected = await BranchPickerDialog.show(
                  context,
                  sessionId: 'session-a',
                  client: client,
                  currentBranch: 'main',
                );
              },
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(BranchPickerDialog), findsNothing);
      expect(selected, isNull);
    });

    testWidgets('double-tap selecting a branch pops once (underlying route still present)', (tester) async {
      final client = _MockBranchClient();
      String? selected;
      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open-picker-btn'),
                  onPressed: () async {
                    selected = await BranchPickerDialog.show(
                      context,
                      sessionId: 'session-a',
                      client: client,
                      currentBranch: 'main',
                    );
                  },
                  child: const Text('Open Picker'),
                ),
              ),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-picker-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(BranchPickerDialog), findsOneWidget);

      // Rapidly double tap on a branch item
      final branchItemFinder = find.byKey(const ValueKey('branch-picker-item-feature/login'));
      await tester.tap(branchItemFinder);
      await tester.tap(branchItemFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Picker is closed
      expect(find.byType(BranchPickerDialog), findsNothing);
      // Underlying route and button are still present
      expect(find.byKey(const ValueKey('open-picker-btn')), findsOneWidget);
      expect(selected, 'feature/login');
    });

    testWidgets('picker row layout with very long branch and upstream names at 540px width has no overflow', (tester) async {
      final client = _MockBranchClient();
      client.mockBranches = [
        const WorkspaceBranchInfo(
          name: 'features/super-extremely-ultra-long-branch-name-that-would-normally-overflow-any-fixed-width-screen-without-ellipsis-guarding-the-layout-completely-1234567890',
          isCurrent: true,
          upstream: 'origin/super-extremely-ultra-long-upstream-remote-tracking-reference-that-exceeds-normal-bounds/main',
          ahead: 12,
          behind: 34,
          lastCommitUnix: 1700000000,
        ),
      ];

      tester.view.physicalSize = const Size(540, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrapWithApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => BranchPickerDialog.show(
                context,
                sessionId: 'session-a',
                client: client,
                currentBranch: 'features/super-extremely-ultra-long-branch-name-that-would-normally-overflow-any-fixed-width-screen-without-ellipsis-guarding-the-layout-completely-1234567890',
              ),
              child: const Text('Open'),
            ),
          ),
          client: client,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check no layout/render overflow exceptions occurred
      expect(tester.takeException(), isNull);
      expect(find.byType(BranchPickerDialog), findsOneWidget);
    });
  });

  group('GitChangesPane branch switcher workflow', () {
    testWidgets('selecting branch sends switchBranch block', (tester) async {
      final client = _MockBranchClient();
      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      // Tap branch chip to open picker
      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      // Select feature/login
      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      expect(client.switchCalls.length, 1);
      expect(client.switchCalls.single.branch, 'feature/login');
      expect(client.switchCalls.single.onDirty, 'block');
    });

    testWidgets('WORKSPACE_DIRTY shows dialog with counts and both options; Cancel sends nothing more', (tester) async {
      final client = _MockBranchClient();
      client.switchErrorToThrow = PcpException(
        'Working directory has uncommitted changes',
        code: 'WORKSPACE_DIRTY',
        details: {'changedFiles': 3, 'untrackedFiles': 2},
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      // Check dialog appears with counts
      expect(find.text('Uncommitted Changes'), findsOneWidget);
      expect(
        find.text(
          'You have 3 modified and 2 untracked files. Switching branch is blocked to protect your changes.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Stash changes and switch'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.byKey(const ValueKey('git-cancel-switch-btn')));
      await tester.pumpAndSettle();

      // Verify no second switch call was made
      expect(client.switchCalls.length, 1);
      expect(client.switchCalls.single.onDirty, 'block');
    });

    testWidgets('choosing Stash sends onDirty: "stash"', (tester) async {
      final client = _MockBranchClient();
      bool firstAttempt = true;
      client.onSwitchBranch = (branch, onDirty) {
        if (firstAttempt) {
          firstAttempt = false;
          throw PcpException(
            'Working directory is dirty',
            code: 'WORKSPACE_DIRTY',
            details: {'changedFiles': 2, 'untrackedFiles': 1},
          );
        }
        return WorkspaceSwitchBranchResult(
          currentBranch: branch,
          stashed: true,
          stashMessage: 'piframe: before switching to $branch',
        );
      };

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      // Confirmation dialog should be visible
      expect(find.byKey(const ValueKey('git-stash-and-switch-btn')), findsOneWidget);

      // Click Stash and switch
      await tester.tap(find.byKey(const ValueKey('git-stash-and-switch-btn')));
      await tester.pumpAndSettle();

      expect(client.switchCalls.length, 2);
      expect(client.switchCalls[0].onDirty, 'block');
      expect(client.switchCalls[1].onDirty, 'stash');

      // Verify snackbar indicates stashed changes
      expect(find.textContaining('Switched to feature/login'), findsOneWidget);
      expect(find.textContaining('Your changes were stashed: piframe: before switching to feature/login'), findsOneWidget);
    });

    testWidgets('success triggers Git Changes refresh + label update', (tester) async {
      final client = _MockBranchClient();
      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main'), findsOneWidget);
      final initialRefreshCount = client.refreshCount;

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      // Verify refresh was triggered
      expect(client.refreshCount, greaterThan(initialRefreshCount));

      // Label updated
      expect(find.text('feature/login'), findsOneWidget);
      expect(find.textContaining('Switched to feature/login'), findsOneWidget);
    });

    testWidgets('failure with stashRetained shows the note', (tester) async {
      final client = _MockBranchClient();
      client.switchErrorToThrow = PcpException(
        'Switch failed and stash retained',
        code: 'BRANCH_SWITCH_FAILED',
        details: {
          'stderr': 'fatal: error switching branch',
          'stashRetained': true,
          'stashMessage': 'piframe: before switching to feature/login (2025-01-01)',
        },
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Branch switch failed'), findsOneWidget);
      expect(find.textContaining('fatal: error switching branch'), findsOneWidget);
      expect(
        find.text(
          'Your changes are safe in the stash: piframe: before switching to feature/login (2025-01-01)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('BRANCH_NOT_FOUND shows message and triggers refresh', (tester) async {
      final client = _MockBranchClient();
      client.switchErrorToThrow = PcpException(
        'Branch not found',
        code: 'BRANCH_NOT_FOUND',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      final initialRefreshCount = client.refreshCount;

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      expect(find.text('Branch not found'), findsOneWidget);
      expect(client.refreshCount, greaterThan(initialRefreshCount));
    });

    testWidgets('busy/read-only rejection shows message "Cannot switch branch while the agent is working"', (tester) async {
      final client = _MockBranchClient();
      client.switchErrorToThrow = PcpException(
        'Repository writes are disabled while the Pi worker is active.',
        code: 'COMMAND_REJECTED',
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      expect(
        find.text('Cannot switch branch while the agent is working'),
        findsOneWidget,
      );
    });

    testWidgets('detached HEAD renders short SHA in branch chip', (tester) async {
      final client = _MockBranchClient();
      client.detached = true;
      client.headShortSha = 'c0ffee1';

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('c0ffee1'), findsOneWidget);
    });

    testWidgets('branch chip onTap is disabled and shows tooltip when agent is working', (tester) async {
      final client = _MockBranchClient();
      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
          agentStatus: AgentStatus.working,
        ),
      );
      await tester.pumpAndSettle();

      // Verify chip has disabled onTap
      final inkWellFinder = find.byKey(const ValueKey('git-branch-chip'));
      expect(inkWellFinder, findsOneWidget);
      final inkWell = tester.widget<InkWell>(inkWellFinder);
      expect(inkWell.onTap, isNull);

      // Verify tooltip explains why
      final tooltipFinder = find.ancestor(
        of: inkWellFinder,
        matching: find.byType(Tooltip),
      );
      expect(tooltipFinder, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, 'Cannot switch branch while the agent is working');

      // Attempting to tap chip does NOT open picker
      await tester.tap(inkWellFinder);
      await tester.pumpAndSettle();
      expect(find.byType(BranchPickerDialog), findsNothing);
    });

    testWidgets('dirty dialog double-click on cancel pops once and preserves root', (tester) async {
      final client = _MockBranchClient();
      client.switchErrorToThrow = PcpException(
        'Working directory has uncommitted changes',
        code: 'WORKSPACE_DIRTY',
        details: {'changedFiles': 1, 'untrackedFiles': 0},
      );

      await tester.pumpWidget(
        _wrapWithApp(
          child: const GitChangesPane(sessionId: 'session-a'),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('git-branch-chip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('branch-picker-item-feature/login')));
      await tester.pumpAndSettle();

      // Dirty dialog visible
      expect(find.byKey(const ValueKey('git-cancel-switch-btn')), findsOneWidget);

      // Double-tap Cancel button rapidly
      await tester.tap(find.byKey(const ValueKey('git-cancel-switch-btn')));
      await tester.tap(find.byKey(const ValueKey('git-cancel-switch-btn')), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.byKey(const ValueKey('git-cancel-switch-btn')), findsNothing);
      // Changes pane is still mounted and visible
      expect(find.byType(GitChangesPane), findsOneWidget);
    });
  });
}

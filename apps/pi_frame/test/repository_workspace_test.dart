import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/domain/errors/user_facing_error.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/frame_list_row.dart';

class _FakeWorkspaceClient extends PcpClient {
  _FakeWorkspaceClient() : super(port: 1, token: 'test');

  String diskContent = 'original\n';
  String diskRevision = 'revision-1';
  bool unsupportedList = false;
  String? requestedDiff;
  final gitActions = <Map<String, dynamic>>[];

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
        {
          'path': 'lib/main.dart',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
        },
        {
          'path': 'notes.txt',
          'status': 'untracked',
          'staged': false,
          'unstaged': true,
        },
      ],
      'totalAdditions': 2,
      'totalDeletions': 1,
    },
  };

  @override
  Future<Map<String, dynamic>> getWorkspaceDiff(
    String sessionId, {
    String? filePath,
  }) async {
    requestedDiff = filePath;
    return {
      'data': {'diff': 'diff --git a/$filePath b/$filePath\\n+updated\\n'},
    };
  }

  @override
  Future<Map<String, dynamic>> workspaceGitAction(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    gitActions.add(payload);
    return {
      'data': {'status': <String, dynamic>{}},
    };
  }

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async {
    if (unsupportedList) {
      throw StateError('Unsupported command type: workspace.listFiles');
    }
    return {
      'data': {
        'rootPath': '/repo',
        'files': [
          {'path': 'lib/main.dart', 'sizeBytes': diskContent.length},
          {'path': 'README.md', 'sizeBytes': 25},
        ],
        'truncated': false,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> readWorkspaceFile(
    String sessionId,
    String path,
  ) async => {
    'data': {
      'rootPath': '/repo',
      'path': path,
      'content': path == 'README.md'
          ? '# Welcome\nDocumentation file.'
          : diskContent,
      'revision': diskRevision,
      'sizeBytes': diskContent.length,
    },
  };

  @override
  Future<Map<String, dynamic>> saveWorkspaceFile(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    if (payload['revision'] != diskRevision) {
      throw StateError('File changed on disk; reload before saving.');
    }
    diskContent = payload['content'] as String;
    diskRevision = 'revision-${DateTime.now().microsecondsSinceEpoch}';
    return {
      'data': {'path': payload['path'], 'revision': diskRevision},
    };
  }
}

/// Long Git list: one staged file and 200 unstaged files, enough to scroll.
class _ManyFilesWorkspaceClient extends _FakeWorkspaceClient {
  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async {
    final files = <Map<String, dynamic>>[
      {
        'path': 'staged-change.dart',
        'status': 'modified',
        'staged': true,
        'unstaged': false,
      },
      for (var i = 1; i <= 200; i++)
        {
          'path': 'generated/file-${i.toString().padLeft(3, '0')}.txt',
          'status': 'untracked',
          'staged': false,
          'unstaged': true,
        },
    ];
    return {
      'data': {
        'isRepository': true,
        'rootPath': '/repo',
        'branch': 'main',
        'files': files,
        'totalAdditions': 205,
        'totalDeletions': 0,
      },
    };
  }
}

/// A clean working tree on branch main.
class _CleanWorkspaceClient extends _FakeWorkspaceClient {
  int refreshCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async {
    refreshCalls++;
    return {
      'data': {
        'isRepository': true,
        'rootPath': '/repo',
        'branch': 'main',
        'files': <Map<String, dynamic>>[],
        'totalAdditions': 0,
        'totalDeletions': 0,
      },
    };
  }
}

/// Holds the status request until [release] is called, to show the loading state.
class _SlowWorkspaceClient extends _FakeWorkspaceClient {
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async {
    await _gate.future;
    return {
      'data': {
        'isRepository': true,
        'rootPath': '/repo',
        'branch': 'main',
        'files': <Map<String, dynamic>>[],
        'totalAdditions': 0,
        'totalDeletions': 0,
      },
    };
  }
}

/// One file with a long name, for the narrow-pane row check.
class _LongNameWorkspaceClient extends _FakeWorkspaceClient {
  // flutter_test draws text with the Ahem font (one em per glyph), so the name
  // is kept short enough to fit a 380 px pane under that metric.
  static const longName = 'git_row_check.dart';

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async {
    return {
      'data': {
        'isRepository': true,
        'rootPath': '/repo',
        'branch': 'main',
        'files': [
          {
            'path': 'packages/pi_frame_theme/lib/src/components/$longName',
            'status': 'modified',
            'staged': false,
            'unstaged': true,
          },
        ],
        'totalAdditions': 1,
        'totalDeletions': 0,
      },
    };
  }
}

/// One staged file. Records each commit message, and fails the commit on request.
class _StagedCommitClient extends _FakeWorkspaceClient {
  _StagedCommitClient({this.failCommit = false});

  final bool failCommit;
  final commitMessages = <String>[];

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
        {
          'path': 'lib/main.dart',
          'status': 'modified',
          'staged': true,
          'unstaged': false,
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
    if (payload['action'] != 'commit') {
      return super.workspaceGitAction(sessionId, payload);
    }
    if (failCommit) throw StateError('nothing to commit');
    commitMessages.add(payload['message'] as String);
    return {
      'data': {'status': <String, dynamic>{}},
    };
  }

  /// The short hash of the new HEAD comes from the branch listing.
  @override
  Future<WorkspaceListBranchesResult> listBranches(String sessionId) async =>
      const WorkspaceListBranchesResult(branches: [], headShortSha: 'a1b2c3d');
}

/// Git row actions show on hover (see FrameListRow), so move the mouse onto the
/// action first, as a user does, and then tap it.
Future<void> _hoverAndTap(WidgetTester tester, Finder target) async {
  final at = tester.getCenter(target);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.moveTo(at);
  await tester.pump();
  await mouse.down(at);
  await mouse.up();
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

void main() {
  test(
    'stale daemon workspace command shows a safe rebuild and restart hint',
    () async {
      final client = _FakeWorkspaceClient()..unsupportedList = true;
      final container = ProviderContainer(
        overrides: [pcpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await container
          .read(repositoryStateProvider('session-a').notifier)
          .loadFiles();
      expect(
        container.read(repositoryStateProvider('session-a')).error,
        isNotNull,
      );
      expect(
        describeError(
          container.read(repositoryStateProvider('session-a')).error!,
          const AppStrings(AppLanguage.it),
        ).hint,
        contains('riavvia il daemon solo quando nessun worker Pi è attivo'),
      );
    },
  );

  test('editor keeps dirty content on revision conflict and clears after explicit retry', () async {
    final client = _FakeWorkspaceClient();
    final container = ProviderContainer(
      overrides: [pcpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final editor = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await editor.loadFiles();
    await editor.selectFile('lib/main.dart');
    editor.edit('lib/main.dart', 'local edit\n');

    client.diskContent = 'external edit\n';
    client.diskRevision = 'revision-external';
    await expectLater(editor.save('lib/main.dart'), throwsA(isA<StateError>()));
    expect(
      editor.currentState.buffers['lib/main.dart']?.content,
      'local edit\n',
    );
    expect(editor.currentState.buffers['lib/main.dart']?.dirty, isTrue);

    final currentDisk = await editor.currentDisk('lib/main.dart');
    await editor.save('lib/main.dart', revisionOverride: currentDisk.revision);
    expect(editor.currentState.buffers['lib/main.dart']?.dirty, isFalse);
    expect(client.diskContent, 'local edit\n');
  });

  testWidgets('Git Changes opens tracked diffs and stages or undoes per file', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('session-a').overrideWith(
            (ref) =>
                SessionStateNotifier('session-a', null)
                  ..state = const SessionState(
                    sessionId: 'session-a',
                    cwd: '/repo',
                    entries: [
                      SessionEntry(
                        id: 'agent-write',
                        role: 'assistant',
                        text: '',
                        timestamp: 1,
                        toolCalls: [
                          ToolExecutionState(
                            toolCallId: 'write-1',
                            toolName: 'write',
                            args: {'path': '/repo/lib/main.dart'},
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GitChangesPane)),
    );
    final repository = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await repository.loadFiles();
    await repository.selectFile('lib/main.dart');
    repository.edit('lib/main.dart', 'manual edit\n');
    await repository.save('lib/main.dart');
    // CHANGES opens by default when it has files.
    await tester.pumpAndSettle();

    // Provenance is an icon; its tooltip carries the origin text.
    expect(find.byTooltip('Tool Pi + salvataggio PiFrame'), findsOneWidget);
    // Name first in its own text; the directory is on the same line.
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(client.requestedDiff, 'lib/main.dart');
    expect(find.textContaining('diff --git a/lib/main.dart'), findsOneWidget);
    // The diff replaces the list in the pane: the Git list is gone until back.
    expect(find.byKey(const ValueKey('git-list')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('git-diff-back-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-list')), findsOneWidget);

    await _hoverAndTap(tester, find.byTooltip('Metti in stage lib/main.dart'));
    await tester.pumpAndSettle();
    expect(client.gitActions.last['action'], 'stage');

    expect(find.byTooltip('Metti in stage notes.txt'), findsOneWidget);
    await _hoverAndTap(tester, find.byTooltip('Metti in stage notes.txt'));
    await tester.pumpAndSettle();
    expect(client.gitActions.last['action'], 'stage');
    expect(client.gitActions.last['paths'], ['notes.txt']);

    await _hoverAndTap(
      tester,
      find.byTooltip('Scarta modifiche a lib/main.dart'),
    );
    expect(find.text('Scartare le modifiche a questo file?'), findsOneWidget);
    await tester.tap(find.text('Scarta modifiche'));
    await tester.pumpAndSettle();
    expect(client.gitActions.last['action'], 'discard');
  });

  testWidgets('Git diff stays in the pane and reviews files by keyboard', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    String position() => tester
        .widget<Text>(find.byKey(const ValueKey('git-diff-position')))
        .data!;

    // Opening a row shows its diff in the pane, not in a dialog.
    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(client.requestedDiff, 'lib/main.dart');
    expect(find.byType(Dialog), findsNothing);
    expect(position(), '1/2');

    // Alt+Down moves to the next file; the list is not rebuilt in between.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(client.requestedDiff, 'notes.txt');
    expect(position(), '2/2');

    // At the last file Alt+Down does nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(position(), '2/2');

    // Escape goes back to the list, and the cursor stays on the file shown.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-pane-diff')), findsNothing);

    // Enter on the focused list opens the file under the cursor again.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(client.requestedDiff, 'notes.txt');
    expect(position(), '2/2');
  });

  testWidgets('Git diff pane buttons step files and keep the window dialog', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('git-diff-prev-btn')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('git-diff-next-btn')));
    await tester.pumpAndSettle();
    expect(client.requestedDiff, 'notes.txt');

    await tester.tap(find.byKey(const ValueKey('git-diff-window-btn')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Chiudi'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('git-diff-position')), findsOneWidget);
  });

  testWidgets('Git discard dialog focuses Annulla and Enter does not discard', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _hoverAndTap(
      tester,
      find.byTooltip('Scarta modifiche a lib/main.dart'),
    );

    expect(find.text('Scartare le modifiche a questo file?'), findsOneWidget);
    expect(
      find.text(
        'Le modifiche in stage e non in stage di questo file verranno rimosse. '
        'L’operazione non può essere annullata.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Annulla'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Scarta modifiche');
    expect(confirm, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(confirm)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      FrameTokens.light.danger,
    );

    // Cancel holds initial focus, so Enter cancels instead of discarding.
    final focusedButton = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<TextButton>();
    expect(focusedButton?.key, const ValueKey('discard-file-cancel-btn'));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Scartare le modifiche a questo file?'), findsNothing);
    expect(
      client.gitActions.where((action) => action['action'] == 'discard'),
      isEmpty,
    );
  });

  testWidgets(
    'Git group headers never paint over the summary line while scrolling',
    (tester) async {
      final client = _ManyFilesWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state = const SessionState(
                  sessionId: 'session-a',
                  cwd: '/repo',
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 420,
                height: 360,
                child: GitChangesPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // CHANGES (200 files) opens by default; STAGED is opened here.
      await tester.tap(find.text('MODIFICHE IN STAGE'));
      await tester.pumpAndSettle();

      final summaryFinder = find.text('201 file');
      final listFinder = find.descendant(
        of: find.byType(GitChangesPane),
        matching: find.byType(ListView),
      );
      expect(summaryFinder, findsOneWidget);
      expect(listFinder, findsOneWidget);
      expect(
        find.ancestor(of: listFinder, matching: find.byType(ClipRect)),
        findsOneWidget,
      );

      final headers = [find.text('MODIFICHE IN STAGE'), find.text('MODIFICHE')];
      // Scroll the list down in steps, then back to the top. Whatever part of a
      // group header is still visible inside the list must sit below the
      // summary line.
      for (final dy in [-200.0, -400.0, -600.0, 1600.0]) {
        await tester.drag(listFinder, Offset(0, dy));
        await tester.pumpAndSettle();
        final summary = tester.getRect(summaryFinder);
        final visibleList = tester.getRect(listFinder);
        expect(visibleList.top, greaterThanOrEqualTo(summary.bottom));
        for (final header in headers) {
          // The lazy list does not build rows scrolled far out of view.
          if (header.evaluate().isEmpty) continue;
          final visible = tester.getRect(header).intersect(visibleList);
          if (visible.isEmpty) continue;
          expect(
            visible.top,
            greaterThanOrEqualTo(summary.bottom),
            reason: 'group header painted over the summary line after dy=$dy',
          );
        }
      }
    },
  );

  testWidgets('Git Changes bottom bar sends fetch, pull, push and sync', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final action in ['fetch', 'pull', 'push', 'sync']) {
      await tester.tap(find.byKey(ValueKey('git-$action-btn')));
      await tester.pumpAndSettle();
      expect(client.gitActions.last['action'], action);
      expect(client.gitActions.last['paths'], isEmpty);
    }
    expect(client.gitActions, hasLength(4));
  });

  testWidgets('Git row right-click menu adds the file to the chat', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('notes.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-menu-open-diff')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-menu-toggle-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-menu-discard')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-menu-copy-path')), findsOneWidget);
    expect(find.byKey(const ValueKey('git-menu-add-chat')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('git-menu-add-chat')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GitChangesPane)),
    );
    // Same path as the editor's "Add file to chat": an @mention in the draft.
    expect(
      container.read(composerDraftProvider('session-a')),
      contains('@notes.txt '),
    );
  });

  testWidgets(
    'Git list is one Tab stop; arrows move, Space stages, Delete discards',
    (tester) async {
      final client = _FakeWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state = const SessionState(
                  sessionId: 'session-a',
                  cwd: '/repo',
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rows are not Tab stops: the list node holds the focus.
      final listNode = Focus.of(
        tester.element(find.byKey(const ValueKey('git-list'))),
      );
      listNode.requestFocus();
      await tester.pumpAndSettle();

      // Entries: STAGED header, CHANGES header, lib/main.dart, notes.txt.
      // Down twice reaches lib/main.dart.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(client.gitActions.last['action'], 'stage');
      expect(client.gitActions.last['paths'], ['lib/main.dart']);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('Scartare le modifiche a questo file?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annulla'));
      await tester.pumpAndSettle();

      // Up one row reaches the CHANGES header; Enter collapses it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('notes.txt'), findsNothing);
    },
  );

  testWidgets('Git writes-disabled line does not move the file rows', (
    tester,
  ) async {
    Future<double?> pumpWith(AgentStatus status) async {
      await tester.pumpWidget(
        ProviderScope(
          // A new key remounts the scope, so the new overrides take effect.
          key: UniqueKey(),
          overrides: [
            pcpClientProvider.overrideWithValue(_FakeWorkspaceClient()),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state = SessionState(
                  sessionId: 'session-a',
                  cwd: '/repo',
                  agentStatus: status,
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 380,
                height: 360,
                child: GitChangesPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.text('notes.txt')).dy;
    }

    final idleY = await pumpWith(AgentStatus.settled);
    expect(find.byKey(const ValueKey('git-writes-disabled')), findsNothing);

    final workingY = await pumpWith(AgentStatus.working);
    expect(find.byKey(const ValueKey('git-writes-disabled')), findsOneWidget);
    expect(
      find.text('Scritture disabilitate mentre Pi sta lavorando.'),
      findsOneWidget,
    );
    expect(workingY, idleY);
  });

  /// Opacity of the row actions of [key]: 0 when hidden, 1 when revealed.
  double rowActionOpacity(WidgetTester tester, String key) {
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Opacity),
          )
          .first,
    );
    return opacity.opacity;
  }

  Future<void> pumpGitRows(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(_FakeWorkspaceClient()),
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const unstagedToggleKey = 'git-unstaged-toggle-notes.txt';

  testWidgets('Git row actions reveal on hover with a desktop pointer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // flutter_test defaults the platform to Android, which is a touch platform.
    // A desktop pointer needs an explicit desktop platform here.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpGitRows(tester);
      expect(rowActionOpacity(tester, unstagedToggleKey), 0);
      final row = find.byKey(const ValueKey('git-row-unstaged-notes.txt'));
      final at = tester.getCenter(row);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.moveTo(at);
      await tester.pumpAndSettle();
      expect(rowActionOpacity(tester, unstagedToggleKey), 1);
      await mouse.removePointer();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Git row actions stay visible in the compact layout', (
    tester,
  ) async {
    // Default test surface is 800 px wide, below the compact breakpoint.
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGitRows(tester);

    expect(rowActionOpacity(tester, unstagedToggleKey), 1);
    expect(
      find.byKey(const ValueKey('git-unstaged-discard-notes.txt')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Git row actions stay visible on a touch platform at desktop width',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // The override must be cleared inside the test body: flutter_test checks
      // the foundation debug variables before tearDown callbacks run.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pumpGitRows(tester);
        expect(rowActionOpacity(tester, unstagedToggleKey), 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  /// One staged file, and a commit that records its message or fails on request.
  Future<void> pumpCommitPane(
    WidgetTester tester,
    _StagedCommitClient client, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final commitButton = find.byKey(const ValueKey('git-commit-btn'));
  final subjectField = find.byKey(const ValueKey('git-commit-subject'));

  testWidgets('Commit form needs a subject and commits with its hash', (
    tester,
  ) async {
    final client = _StagedCommitClient();
    await pumpCommitPane(tester, client);

    expect(tester.widget<FilledButton>(commitButton).onPressed, isNull);
    await tester.tap(subjectField);
    await tester.enterText(subjectField, 'Fix the diff pane');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(commitButton).onPressed, isNotNull);

    await tester.tap(commitButton);
    await tester.pumpAndSettle();
    expect(client.commitMessages, ['Fix the diff pane']);
    // The success snackbar carries the short hash of the new HEAD.
    expect(find.text('Commit a1b2c3d creato.'), findsOneWidget);
    expect(tester.widget<TextField>(subjectField).controller!.text, isEmpty);
  });

  testWidgets('Ctrl+Enter commits the subject and the optional body', (
    tester,
  ) async {
    final client = _StagedCommitClient();
    await pumpCommitPane(tester, client);

    await tester.tap(find.text('Aggiungi descrizione'));
    await tester.pumpAndSettle();
    await tester.tap(subjectField);
    await tester.enterText(subjectField, 'Add commit form');
    await tester.tap(find.byKey(const ValueKey('git-commit-body')));
    await tester.enterText(
      find.byKey(const ValueKey('git-commit-body')),
      'Subject and body are sent together.',
    );
    await tester.pumpAndSettle();

    await tester.tap(subjectField);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(client.commitMessages, [
      'Add commit form\n\nSubject and body are sent together.',
    ]);
  });

  testWidgets(
    'Subject past 72 characters shows the counter in the warning tone',
    (tester) async {
      final client = _StagedCommitClient();
      await pumpCommitPane(tester, client);

      final counter = find.byKey(const ValueKey('git-commit-subject-counter'));
      await tester.tap(subjectField);
      await tester.enterText(subjectField, 'x' * 72);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(counter).data, '72/72');
      expect(
        tester.widget<Text>(counter).style?.color,
        isNot(FrameTokens.light.warning),
      );

      await tester.enterText(subjectField, 'x' * 73);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(counter).data, '73/72');
      expect(
        tester.widget<Text>(counter).style?.color,
        FrameTokens.light.warning,
      );
      // The soft guide does not block the commit.
      expect(tester.widget<FilledButton>(commitButton).onPressed, isNotNull);
    },
  );

  testWidgets('Compact layout spans Commit under the four remote buttons', (
    tester,
  ) async {
    final fetch = find.byKey(const ValueKey('git-fetch-btn'));
    final sync = find.byKey(const ValueKey('git-sync-btn'));

    await pumpCommitPane(
      tester,
      _StagedCommitClient(),
      size: const Size(800, 900),
    );
    expect(
      tester.getTopLeft(commitButton).dx,
      closeTo(tester.getTopLeft(fetch).dx, 0.5),
    );
    expect(
      tester.getBottomRight(commitButton).dx,
      closeTo(tester.getBottomRight(sync).dx, 0.5),
    );
    // Commit sits below the remote buttons.
    expect(
      tester.getTopLeft(commitButton).dy,
      greaterThan(tester.getBottomLeft(fetch).dy),
    );
  });

  testWidgets('Wide layout keeps Commit at its natural width, on the right', (
    tester,
  ) async {
    await pumpCommitPane(tester, _StagedCommitClient());
    final fetch = find.byKey(const ValueKey('git-fetch-btn'));
    expect(
      tester.getTopLeft(commitButton).dx,
      greaterThan(tester.getTopLeft(fetch).dx),
    );
    expect(tester.getSize(commitButton).width, lessThan(200));
  });

  testWidgets('A failed commit shows its error inline and keeps the message', (
    tester,
  ) async {
    final client = _StagedCommitClient(failCommit: true);
    await pumpCommitPane(tester, client);

    await tester.tap(subjectField);
    await tester.enterText(subjectField, 'Will fail');
    await tester.pumpAndSettle();
    await tester.tap(commitButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-commit-error')), findsOneWidget);
    expect(
      tester.widget<TextField>(subjectField).controller!.text,
      'Will fail',
    );
  });

  testWidgets('Git clean tree shows an empty state with a refresh action', (
    tester,
  ) async {
    final client = _CleanWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('git-empty')), findsOneWidget);
    expect(find.text('Nessuna modifica'), findsOneWidget);
    expect(
      find.text('Il ramo main non ha modifiche da rivedere.'),
      findsOneWidget,
    );
    final refreshCalls = client.refreshCalls;
    await tester.tap(find.byKey(const ValueKey('git-empty-action')));
    await tester.pumpAndSettle();
    expect(client.refreshCalls, greaterThan(refreshCalls));
  });

  testWidgets('Git list shows skeleton rows while the status is loading', (
    tester,
  ) async {
    final client = _SlowWorkspaceClient();
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
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('git-loading')), findsOneWidget);
    expect(find.text('Lettura stato Git…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    client.release();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-loading')), findsNothing);
  });

  testWidgets(
    'Git rows keep the whole file name on one line in a 380 px pane',
    (tester) async {
      final client = _LongNameWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state = const SessionState(
                  sessionId: 'session-a',
                  cwd: '/repo',
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 380,
                height: 360,
                child: GitChangesPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // CHANGES has files, so it is open by default.
      final nameFinder = find.text(_LongNameWorkspaceClient.longName);
      expect(nameFinder, findsOneWidget);
      final nameText = tester.widget<Text>(nameFinder);
      final natural = TextPainter(
        text: TextSpan(
          text: _LongNameWorkspaceClient.longName,
          style: nameText.style,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(natural.dispose);
      // Not truncated: the laid-out name is as wide as its natural width.
      expect(
        tester.getSize(nameFinder).width,
        greaterThanOrEqualTo(natural.width - 0.5),
      );
      // The row is one line high: 28 px.
      final row = tester.getRect(find.byType(FrameListRow).first);
      expect(row.height, lessThanOrEqualTo(FrameSize.rowList));
    },
  );

  testWidgets('Composer can add a repository file to prompt context', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(body: Composer(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Allega file, link o immagine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File dal repository'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lib/main.dart'));
    await tester.pumpAndSettle();

    final draft = ProviderScope.containerOf(
      tester.element(find.byType(Composer)),
    ).read(composerDraftProvider('session-a'));
    expect(draft, contains('@lib/main.dart'));
  });

  testWidgets('Composer adds selected code with exact file and line range', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
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
          home: const Scaffold(
            body: Row(
              children: [
                Expanded(child: RepositoryPane(sessionId: 'session-a')),
                Expanded(child: Composer(sessionId: 'session-a')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepositoryPane)),
    );
    final repository = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await repository.loadFiles();
    await repository.selectFile('lib/main.dart');
    await tester.pumpAndSettle();

    final fieldFinder = find.byKey(
      const ValueKey('repository-editor-session-a'),
    );
    final editorField = tester.widget<TextField>(fieldFinder);
    editorField.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 8,
    );
    await tester.pump();
    final editableFinder = find.descendant(
      of: fieldFinder,
      matching: find.byType(EditableText),
    );
    final editorState = tester.state<EditableTextState>(editableFinder);
    final menu = editorField.contextMenuBuilder!(
      tester.element(fieldFinder),
      editorState,
    ) as AdaptiveTextSelectionToolbar;
    menu.buttonItems!
        .singleWhere((item) => item.label == 'Aggiungi alla chat')
        .onPressed!
        .call();

    final draft = container.read(composerDraftProvider('session-a'));
    expect(draft, contains('lib/main.dart:1-1'));
    expect(draft, contains('original'));
  });

  testWidgets('session switch cancel preserves dirty editor buffer', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          activeSessionIdProvider.overrideWith((ref) => 'session-a'),
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
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => switchSessionSafely(context, ref, 'session-b'),
                child: const Text('Switch session'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Switch session')),
    );
    final editor = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await editor.loadFiles();
    await editor.selectFile('lib/main.dart');
    editor.edit('lib/main.dart', 'unsaved\n');

    await tester.tap(find.text('Switch session'));
    await tester.pumpAndSettle();
    expect(find.text('Modifiche non salvate'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), 'session-a');
    expect(editor.currentState.buffers['lib/main.dart']?.dirty, isTrue);
  });

  testWidgets(
    'RepositoryPane displays full-width treeview without empty editor, expands/collapses folders and closes editor',
    (tester) async {
      final client = _FakeWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state = const SessionState(
                  sessionId: 'session-a',
                  cwd: '/repo',
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: RepositoryPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no file is selected: editor field does NOT exist! No wasted space!
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );
      expect(find.text('Seleziona un file'), findsNothing);

      // Hierarchical folder 'lib' is present in tree; starts collapsed by default
      expect(find.text('lib'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);

      // Tap 'lib' folder row to expand it
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();

      // Child 'main.dart' is now visible!
      expect(find.text('main.dart'), findsOneWidget);

      // Tap 'lib' again to collapse it
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsNothing);

      // Tap 'lib' again to expand it
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      // Tap the file to open it in the editor
      await tester.tap(find.text('main.dart'));
      await tester.pumpAndSettle();

      // Now editor is opened
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsOneWidget,
      );
      expect(find.byTooltip('Chiudi file'), findsOneWidget);

      // Click close button to close the editor
      await tester.tap(find.byTooltip('Chiudi file'));
      await tester.pumpAndSettle();

      // Returns to full-width tree view, editor is gone
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'RepositoryPane renders .md files in formatted preview by default and toggles to editor',
    (tester) async {
      final client = _FakeWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state = const SessionState(
                  sessionId: 'session-a',
                  cwd: '/repo',
                ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: RepositoryPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open README.md
      expect(find.text('README.md'), findsOneWidget);
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      // In preview mode by default: preview widget is present, raw editor TextField is absent
      expect(
        find.byKey(const ValueKey('repository-md-preview-README.md')),
        findsOneWidget,
      );
      expect(find.text('Welcome'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );

      // Markdown toggle button is visible
      final toggleBtn = find.byKey(
        const ValueKey('repository-markdown-toggle-btn'),
      );
      expect(toggleBtn, findsOneWidget);

      // Tap toggle button to switch to raw editor
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('repository-md-preview-README.md')),
        findsNothing,
      );

      // Tap toggle button again to return to preview mode
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('repository-md-preview-README.md')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );
    },
  );
}

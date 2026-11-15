import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/layout/layout_store.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/command_palette/command_palette.dart';
import 'package:pi_frame/features/session_changes/session_changes_provider.dart';
import 'package:pi_frame/features/side/side_provider.dart';
import 'package:pi_frame/features/workspace/git/git_diff_view.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/escape_layers.dart';
import 'package:pi_frame/ui/frame_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Plan task 6.3 / section 13 item 4: Escape closes the topmost open layer, and only that one.
///
/// Each test opens one layer (or a stack of layers), presses Escape, and asserts that
/// exactly the topmost layer closed. The shell tests drive the real [AppShell] key
/// routing. The in-pane diff test uses a host that routes Escape the way the shell does.

ProviderContainer _shellContainer() => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => 'session_1'),
    connectionStateProvider.overrideWith(
      (ref) => Stream.value(DaemonConnectionState.connected),
    ),
    sessionListProvider.overrideWith((ref) async => const []),
    sessionStateFamily('session_1').overrideWith(
      (ref) =>
          SessionStateNotifier('session_1', null)
            ..state = SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1')
        .overrideWith((ref) => RepositoryController('session_1', () => null)),
  ],
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_escape_test_');
    LayoutStore.instance.setStorageFileForTesting(
      File('${tempDir.path}/layout.json'),
    );
  });

  tearDown(() {
    LayoutStore.instance.setStorageFileForTesting(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pressEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  ScaffoldState scaffold(WidgetTester tester) =>
      tester.state<ScaffoldState>(find.byType(Scaffold).first);

  Future<void> openEndDrawer(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('shell-context-drawer-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isTrue);
  }

  Finder composerInput() => find
      .descendant(
        of: find.byKey(const ValueKey('focus-region-composer')),
        matching: find.byType(EditableText),
      )
      .first;

  /// Returns focus to the composer input, the way a user would after a drawer opens.
  Future<void> focusComposer(WidgetTester tester) async {
    final input = tester.state<EditableTextState>(composerInput());
    input.widget.focusNode.requestFocus();
    await tester.pump();
  }

  testWidgets(
    'menu: Escape closes the composer slash menu, not the drawer under it',
    (tester) async {
      final container = _shellContainer();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      await openEndDrawer(tester);
      await focusComposer(tester);
      await tester.enterText(composerInput(), '/');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('composer-slash-menu')), findsOneWidget);

      await pressEscape(tester);
      expect(find.byKey(const ValueKey('composer-slash-menu')), findsNothing);
      expect(scaffold(tester).isEndDrawerOpen, isTrue);

      await pressEscape(tester);
      expect(scaffold(tester).isEndDrawerOpen, isFalse);
    },
  );

  testWidgets(
    'click-opened FrameDialog: Escape closes the dialog, the side conversation stays open',
    (tester) async {
      final container = _shellContainer();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      container.read(sideThreadFamily('session_1').notifier).state =
          const SideThreadState(
            parentSessionId: 'session_1',
            sideId: 'side_1',
            streamId: 'stream_1',
            status: 'active',
            isOpen: true,
          );
      // The side panel opens with a width animation: let it finish before tapping.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // A draft makes Close ask for confirmation through a click-launched FrameDialog.
      await tester.enterText(
        find.byKey(const ValueKey('side-mini-composer-input')),
        'bozza',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('side-close-btn')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FrameDialog<bool>), findsOneWidget);

      await pressEscape(tester);
      expect(find.byType(FrameDialog<bool>), findsNothing);
      expect(container.read(sideThreadFamily('session_1')).isOpen, isTrue);
    },
  );

  testWidgets(
    'context drawer: Escape closes only the drawer, Review mode stays open',
    (tester) async {
      final container = _shellContainer();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      container.read(isReviewingChangesProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 500));
      await openEndDrawer(tester);

      await pressEscape(tester);
      expect(scaffold(tester).isEndDrawerOpen, isFalse);
      expect(container.read(isReviewingChangesProvider), isTrue);
    },
  );

  testWidgets(
    'Review mode under Settings: Settings covers Review, so Escape closes Settings first',
    (tester) async {
      final container = _shellContainer();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      container.read(isReviewingChangesProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 500));
      container.read(showSettingsProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 500));

      // Settings replaces the workspace, so the Review pane is not mounted while it
      // is open. Its layer is not registered, and Settings is the visible top layer.
      await pressEscape(tester);
      expect(container.read(showSettingsProvider), isFalse);
      expect(container.read(isReviewingChangesProvider), isTrue);

      // With Settings closed, Review is back on screen and closes on the next Escape.
      await pressEscape(tester);
      expect(container.read(isReviewingChangesProvider), isFalse);
    },
  );

  testWidgets('Review mode: Escape closes Review', (tester) async {
    final container = _shellContainer();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    container.read(isReviewingChangesProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 500));

    await pressEscape(tester);
    expect(container.read(isReviewingChangesProvider), isFalse);
    expect(scaffold(tester).isEndDrawerOpen, isFalse);
  });

  testWidgets('Settings: Escape closes Settings and nothing else', (
    tester,
  ) async {
    final container = _shellContainer();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    container.read(showSettingsProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 500));

    await pressEscape(tester);
    expect(container.read(showSettingsProvider), isFalse);
    expect(container.read(isReviewingChangesProvider), isFalse);
    expect(scaffold(tester).isEndDrawerOpen, isFalse);
  });

  testWidgets('side conversation: Escape closes it when the draft is empty', (
    tester,
  ) async {
    final container = _shellContainer();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    container.read(sideThreadFamily('session_1').notifier).state =
        const SideThreadState(
          parentSessionId: 'session_1',
          sideId: 'side_1',
          streamId: 'stream_1',
          status: 'active',
          isOpen: true,
        );
    await tester.pump(const Duration(milliseconds: 500));

    await pressEscape(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FrameDialog<bool>), findsNothing);
    expect(container.read(sideThreadFamily('session_1')).isOpen, isFalse);
  });

  testWidgets(
    'command palette: Escape closes the palette and leaves Settings open',
    (tester) async {
      final container = _shellContainer();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      container.read(showSettingsProvider.notifier).state = true;
      await tester.pump(const Duration(milliseconds: 500));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CommandPalette), findsOneWidget);

      await pressEscape(tester);
      expect(find.byType(CommandPalette), findsNothing);
      expect(container.read(showSettingsProvider), isTrue);
    },
  );

  testWidgets('in-pane Git diff: Escape closes the diff, the layer below stays open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        pcpClientProvider.overrideWithValue(_GitClient()),
        sessionStateFamily('session-a').overrideWith(
          (ref) => SessionStateNotifier('session-a', null)
            ..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
        ),
      ],
    );
    addTearDown(container.dispose);

    // A layer below the diff, registered first, as Settings would be.
    final lowerLog = <String>[];
    container.read(escapeLayersProvider).register(EscapeLayer.settings, () {
      lowerLog.add('settings');
      return true;
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          // Routes Escape the way the app shell does: to the topmost open layer.
          home: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey != LogicalKeyboardKey.escape) {
                return KeyEventResult.ignored;
              }
              return container.read(escapeLayersProvider).closeTopmost()
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored;
            },
            child: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Focus the list, move the cursor onto notes.txt, and open it with Enter.
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
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(GitDiffPane), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GitDiffPane), findsNothing);
    expect(lowerLog, isEmpty);
    expect(tester.takeException(), isNull);

    // The layer below is still registered and closes on the next Escape.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(lowerLog, ['settings']);
  });
}

/// Git status for one unstaged file, enough to open its diff.
class _GitClient extends PcpClient {
  _GitClient() : super(port: 1, token: 'test');

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
          'path': 'notes.txt',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
        },
      ],
      'totalAdditions': 1,
      'totalDeletions': 0,
    },
  };

  @override
  Future<WorkspaceListBranchesResult> listBranches(String sessionId) async =>
      const WorkspaceListBranchesResult(branches: [], headShortSha: 'a1b2c3d');
}

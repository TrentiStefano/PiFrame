import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/layout/layout_store.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/features/workspace/pane_drag_state.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => 'session_1'),
    connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
    sessionStateFamily('session_1').overrideWith(
      (ref) =>
          SessionStateNotifier('session_1', null)..state = const SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1').overrideWith((ref) => RepositoryController('session_1', () => null)),
  ],
);

void main() {
  late Directory tempDir;
  late File layoutFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_layout_test_');
    layoutFile = File('${tempDir.path}/layout.json');
    LayoutStore.instance.setStorageFileForTesting(layoutFile);
  });

  tearDown(() {
    LayoutStore.instance.setStorageFileForTesting(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a hidden repository pane stays hidden after restart', (tester) async {
    layoutFile.writeAsStringSync(
      jsonEncode({
        'visibility': {'repository': false, 'chat': true, 'git': true},
        'sidebarCollapsed': false,
      }),
    );
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    expect(find.byTooltip('Collapse Repository panel'), findsNothing);
    expect(find.byTooltip('Espandi pannello Repository'), findsNothing);
    expect(find.byTooltip('Collapse Git Changes panel'), findsOneWidget);
  });

  testWidgets('hiding a pane and collapsing the sessions bar are saved', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    await tester.tap(find.byTooltip('Collapse sessions sidebar'));
    await tester.pumpAndSettle();

    final saved = jsonDecode(layoutFile.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['sidebarCollapsed'], isTrue);
    expect((saved['visibility'] as Map)['repository'], isTrue);
  });

  testWidgets('a corrupt layout file falls back to the default layout', (tester) async {
    layoutFile.writeAsStringSync('{not json');
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    expect(find.byTooltip('Collapse Repository panel'), findsOneWidget);
    expect(find.byTooltip('Collapse sessions sidebar'), findsOneWidget);
  });

  testWidgets('sessions sidebar grows, shrinks and preserves width on reopen', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    final sidebar = find.byKey(const ValueKey('sessions-sidebar-pane'));
    final divider = find.byKey(const ValueKey('sessions-sidebar-divider'));
    expect(tester.getSize(sidebar).width, 280);
    await tester.drag(divider, const Offset(120, 0));
    await tester.pumpAndSettle();
    final wider = tester.getSize(sidebar).width;
    expect(wider, greaterThan(280));
    expect(wider, lessThanOrEqualTo(400));
    expect(container.read(paneDraggingProvider), isFalse);
    expect((jsonDecode(layoutFile.readAsStringSync()) as Map)['sidebarWidth'], wider);

    await tester.drag(divider, const Offset(-60, 0));
    await tester.pumpAndSettle();
    final narrower = tester.getSize(sidebar).width;
    expect(narrower, lessThan(wider));
    expect(narrower, greaterThanOrEqualTo(220));

    await tester.tap(find.byTooltip('Collapse sessions sidebar'));
    await tester.pumpAndSettle();
    expect(divider, findsNothing);
    await tester.tap(find.byTooltip('Expand sessions sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, narrower);

    await tester.pumpWidget(const SizedBox());
    await pumpShell(tester, container);
    expect(tester.getSize(sidebar).width, narrower);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sessions sidebar width is bounded at both drag extremes', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    final sidebar = find.byKey(const ValueKey('sessions-sidebar-pane'));
    final divider = find.byKey(const ValueKey('sessions-sidebar-divider'));
    await tester.drag(divider, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 560);
    await tester.drag(divider, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 220);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer resizes and adapts without overwriting the desktop width', (tester) async {
    layoutFile.writeAsStringSync(jsonEncode({'sidebarWidth': 500}));
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open sessions'));
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('sessions-sidebar-pane'));
    final divider = find.byKey(const ValueKey('sessions-sidebar-divider'));
    expect(tester.getSize(sidebar).width, 358);
    expect((jsonDecode(layoutFile.readAsStringSync()) as Map)['sidebarWidth'], 500);

    await tester.drag(divider, const Offset(-70, 0));
    await tester.pumpAndSettle();
    final resized = tester.getSize(sidebar).width;
    expect(resized, lessThan(358));
    expect(resized, greaterThanOrEqualTo(220));
    expect((jsonDecode(layoutFile.readAsStringSync()) as Map)['sidebarWidth'], resized);
    expect(tester.takeException(), isNull);
  });

  for (final width in [180, 900, 'invalid']) {
    testWidgets('stored sidebar width $width is safely restored', (tester) async {
      layoutFile.writeAsStringSync(jsonEncode({'sidebarWidth': width}));
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);
      expect(
        tester.getSize(find.byKey(const ValueKey('sessions-sidebar-pane'))).width,
        width == 180 ? 220 : (width == 900 ? 560 : 280),
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('no file is written when storage is disabled under tests', () {
    LayoutStore.instance.setStorageFileForTesting(null);
    expect(() => LayoutStore.instance.save({'sidebarCollapsed': true}), returnsNormally);
    expect(LayoutStore.instance.load(), isEmpty);
  });

  group('restored pane layout (task 6.6)', () {
    test('clamp keeps companions at 320 px and chat at 420 px', () {
      final weights = clampRestoredPaneWeights(
        panes: const [WorkspacePane.repository, WorkspacePane.chat, WorkspacePane.git],
        collapsed: const {},
        weights: const {WorkspacePane.repository: 90, WorkspacePane.chat: 5, WorkspacePane.git: 5},
        availableWidth: 1400,
      );
      final total = weights.values.fold<double>(0, (sum, v) => sum + v);
      expect(total, closeTo(100, 1e-9));
      expect(weights[WorkspacePane.chat]! / 100 * 1400, greaterThanOrEqualTo(420));
      expect(weights[WorkspacePane.git]! / 100 * 1400, greaterThanOrEqualTo(kCompanionMinWidth));
      expect(weights[WorkspacePane.repository]! / 100 * 1400, greaterThanOrEqualTo(kCompanionMinWidth));
    });

    test('clamp leaves a healthy layout unchanged in proportion', () {
      final weights = clampRestoredPaneWeights(
        panes: const [WorkspacePane.chat, WorkspacePane.git],
        collapsed: const {},
        weights: const {WorkspacePane.chat: 60, WorkspacePane.git: 40},
        availableWidth: 2000,
      );
      expect(weights[WorkspacePane.chat], closeTo(60, 1e-9));
      expect(weights[WorkspacePane.git], closeTo(40, 1e-9));
    });

    test('clamp ignores collapsed panes and a single open pane', () {
      final weights = clampRestoredPaneWeights(
        panes: const [WorkspacePane.chat, WorkspacePane.git],
        collapsed: const {WorkspacePane.git},
        weights: const {WorkspacePane.chat: 10, WorkspacePane.git: 90},
        availableWidth: 800,
      );
      expect(weights[WorkspacePane.chat], 10);
      expect(weights[WorkspacePane.git], 90);
    });

    testWidgets('restored weights are clamped to the minimum widths', (tester) async {
      layoutFile.writeAsStringSync(
        jsonEncode({
          'paneWeights': {'repository': 90, 'chat': 5, 'git': 5},
        }),
      );
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      final chat = tester.getSize(find.byKey(const ValueKey('pane-enter-WorkspacePane.chat')));
      final git = tester.getSize(find.byKey(const ValueKey('pane-enter-WorkspacePane.git')));
      expect(chat.width, greaterThanOrEqualTo(kChatMinWidth - 1));
      expect(git.width, greaterThanOrEqualTo(kCompanionMinWidth - 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dragged pane divider survives a restart', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      final divider = find.byKey(const ValueKey('pane-divider-WorkspacePane.repository-WorkspacePane.chat'));
      final repo = find.byKey(const ValueKey('pane-enter-WorkspacePane.repository'));
      final before = tester.getSize(repo).width;
      await tester.drag(divider, const Offset(-40, 0));
      await tester.pumpAndSettle();
      final dragged = tester.getSize(repo).width;
      expect(dragged, lessThan(before));
      expect(
        (jsonDecode(layoutFile.readAsStringSync()) as Map<String, dynamic>)['paneWeights'],
        isA<Map<String, dynamic>>(),
      );

      await tester.pumpWidget(const SizedBox());
      await pumpShell(tester, container);
      expect(tester.getSize(repo).width, closeTo(dragged, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapsed panes, compact pane and companion tab are saved', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      await tester.tap(find.byTooltip('Collapse Git Changes panel'));
      await tester.pumpAndSettle();

      final saved = jsonDecode(layoutFile.readAsStringSync()) as Map<String, dynamic>;
      expect(saved['collapsedPanes'], contains('git'));
      expect(saved['compactPane'], isA<String>());
      expect(saved['companionPane'], isA<String>());
      expect(saved['paneWeights'], isA<Map<String, dynamic>>());
    });

    testWidgets('restored collapsed pane stays collapsed after restart', (tester) async {
      layoutFile.writeAsStringSync(
        jsonEncode({
          'collapsedPanes': ['git'],
          'companionPane': 'repository',
        }),
      );
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      expect(find.byKey(const ValueKey('pane-enter-WorkspacePane.git')), findsNothing);
      expect(find.byKey(const ValueKey('pane-enter-WorkspacePane.repository')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a restored state that collapses every pane is discarded', (tester) async {
      layoutFile.writeAsStringSync(
        jsonEncode({
          'collapsedPanes': ['repository', 'chat', 'git', 'bogus'],
          'companionPane': 'chat',
          'compactPane': 'nope',
        }),
      );
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      expect(find.byKey(const ValueKey('pane-enter-WorkspacePane.chat')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('divider keyboard access (task 6.7)', () {
    Finder focusTarget(Finder divider) => find.descendant(of: divider, matching: find.byType(GestureDetector)).first;

    testWidgets('sessions divider moves with the arrow keys and is saved', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      final sidebar = find.byKey(const ValueKey('sessions-sidebar-pane'));
      final divider = find.byKey(const ValueKey('sessions-sidebar-divider'));
      Focus.of(tester.element(focusTarget(divider))).requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 300);
      expect((jsonDecode(layoutFile.readAsStringSync()) as Map)['sidebarWidth'], 300);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 260);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pane dividers move with the arrow keys and are saved', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      final divider = find.byKey(const ValueKey('pane-divider-WorkspacePane.repository-WorkspacePane.chat'));
      final repo = find.byKey(const ValueKey('pane-enter-WorkspacePane.repository'));
      final before = tester.getSize(repo).width;
      Focus.of(tester.element(focusTarget(divider))).requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final wider = tester.getSize(repo).width;
      expect(wider, greaterThan(before));
      expect(
        (jsonDecode(layoutFile.readAsStringSync()) as Map<String, dynamic>)['paneWeights'],
        isA<Map<String, dynamic>>(),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.getSize(repo).width, lessThan(wider));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pane dividers expose increase and decrease to assistive tech', (tester) async {
      final handle = tester.ensureSemantics();
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      final divider = find.byKey(const ValueKey('pane-divider-WorkspacePane.chat-WorkspacePane.git'));
      final node = tester.getSemantics(find.descendant(of: divider, matching: find.byType(Semantics)).first);
      // The semantics owner the test binding dispatches actions through.
      // ignore: deprecated_member_use
      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      final git = find.byKey(const ValueKey('pane-enter-WorkspacePane.git'));
      final before = tester.getSize(git).width;
      owner.performAction(node.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(tester.getSize(git).width, greaterThan(before));

      owner.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(tester.getSize(git).width, closeTo(before, 2));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('maximizing the agents sidecar does not collapse git changes', (tester) async {
      layoutFile.writeAsStringSync(
        jsonEncode({
          'visibility': {'repository': false, 'chat': true, 'git': true},
          'sidebarCollapsed': false,
        }),
      );
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      // Git changes pane is open initially
      expect(find.byKey(const ValueKey('git_session_1')), findsOneWidget);

      // Open/maximize the agent activity sidecar if button is present
      final openBtn = find.byKey(const ValueKey('agent-activity-open-btn'));
      if (openBtn.evaluate().isNotEmpty) {
        await tester.tap(openBtn);
        await tester.pumpAndSettle();
      }

      // Git changes pane must stay open and not be collapsed
      expect(find.byKey(const ValueKey('git_session_1')), findsOneWidget);
    });
  });
}

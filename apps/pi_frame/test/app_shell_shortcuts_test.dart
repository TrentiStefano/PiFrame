import 'dart:convert';
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
import 'package:pi_frame/features/workspace/repository_workspace.dart';

ProviderContainer _container({
  List<String> sessionIds = const ['session_1'],
  bool withClient = false,
  List<Map<String, dynamic>>? sessions,
}) => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => sessionIds.first),
    connectionStateProvider.overrideWith(
      (ref) => Stream.value(DaemonConnectionState.connected),
    ),
    if (withClient)
      pcpClientProvider.overrideWithValue(
            PcpClient(port: 1, token: 'test'),
          ),
    sessionListProvider.overrideWith((ref) async => sessions ?? const []),
    for (final id in sessionIds) ...[
      sessionStateFamily(id).overrideWith(
        (ref) => SessionStateNotifier(id, null)
          ..state = SessionState(sessionId: id, cwd: 'C:/repo'),
      ),
      repositoryStateProvider(id)
          .overrideWith((ref) => RepositoryController(id, () => null)),
    ],
  ],
);

void main() {
  late Directory tempDir;
  late File layoutFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_shortcuts_test_');
    layoutFile = File('${tempDir.path}/layout.json');
    LayoutStore.instance.setStorageFileForTesting(layoutFile);
  });

  tearDown(() {
    LayoutStore.instance.setStorageFileForTesting(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(
    WidgetTester tester,
    ProviderContainer container, {
    double width = 1920,
  }) async {
    tester.view.physicalSize = Size(width, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    // Bounded pumps: a disconnected client keeps an indicator animating forever.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Presses [key] with [modifier] held, as one chord.
  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Ctrl+N opens the new session chooser', (tester) async {
    final container = _container(withClient: true);
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    expect(find.byType(AlertDialog), findsNothing);

    await press(tester, LogicalKeyboardKey.keyN);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cmd+N also opens the new session chooser', (tester) async {
    final container = _container(withClient: true);
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    await press(
      tester,
      LogicalKeyboardKey.keyN,
      modifier: LogicalKeyboardKey.metaLeft,
    );

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Ctrl+, opens settings', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    expect(container.read(showSettingsProvider), isFalse);

    await press(tester, LogicalKeyboardKey.comma);

    expect(container.read(showSettingsProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+B hides and shows the docked sessions rail', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    final rail = find.byKey(const ValueKey('sessions-sidebar-pane'));
    expect(rail, findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyB);
    expect(rail, findsNothing);
    expect(
      (jsonDecode(layoutFile.readAsStringSync()) as Map)['sidebarCollapsed'],
      isTrue,
    );

    await press(tester, LogicalKeyboardKey.keyB);
    expect(rail, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+Shift+B keeps its side conversation meaning, not the rail', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    await press(tester, LogicalKeyboardKey.keyB, shift: true);

    expect(
      find.byKey(const ValueKey('sessions-sidebar-pane')),
      findsOneWidget,
    );
  });

  testWidgets('Ctrl+Tab switches to the previously active session', (
    tester,
  ) async {
    final sessions = [
      {'id': 'session_1'},
      {'id': 'session_2'},
    ];
    final container = _container(
      sessionIds: const ['session_1', 'session_2'],
      sessions: sessions,
    );
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    container.read(activeSessionIdProvider.notifier).state = 'session_2';
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(activeSessionIdProvider), 'session_2');

    await press(tester, LogicalKeyboardKey.tab);
    expect(container.read(activeSessionIdProvider), 'session_1');

    await press(tester, LogicalKeyboardKey.tab);
    expect(container.read(activeSessionIdProvider), 'session_2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+Tab does nothing when the previous session is gone', (
    tester,
  ) async {
    final container = _container(
      sessionIds: const ['session_1', 'session_2'],
      sessions: [
        {'id': 'session_2'},
      ],
    );
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    container.read(activeSessionIdProvider.notifier).state = 'session_2';
    await tester.pump(const Duration(milliseconds: 500));
    await press(tester, LogicalKeyboardKey.tab);

    expect(container.read(activeSessionIdProvider), 'session_2');
  });
}

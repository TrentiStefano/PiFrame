import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/layout/layout_store.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/settings/settings_view.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';

/// Title bar layout and controls (plan task 5.4).
ProviderContainer _container() => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => 'session_1'),
    connectionStateProvider.overrideWith(
      (ref) => Stream.value(DaemonConnectionState.connected),
    ),
    sessionListProvider.overrideWith((ref) async => const []),
    sessionStateFamily('session_1').overrideWith(
      (ref) => SessionStateNotifier('session_1', null)
        ..state = SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1')
        .overrideWith((ref) => RepositoryController('session_1', () => null)),
  ],
);

Finder _textInside(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(Text));

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_title_bar_test_');
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
    ProviderContainer container, {
    required double width,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
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

  testWidgets('context drawer button is labelled from 1100 px and icon-only below', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);

    await pumpShell(tester, container, width: 1920);
    expect(
      _textInside(const ValueKey('shell-context-drawer-button')),
      findsOneWidget,
    );

    await pumpShell(tester, container, width: 1000);
    expect(
      find.byKey(const ValueKey('shell-context-drawer-button')),
      findsOneWidget,
    );
    expect(
      _textInside(const ValueKey('shell-context-drawer-button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection indicator keeps its label from 920 px and is dot-only below', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);

    await pumpShell(tester, container, width: 1920);
    expect(
      _textInside(const ValueKey('shell-connection-indicator')),
      findsOneWidget,
    );

    await pumpShell(tester, container, width: 880);
    final indicator = find.byKey(const ValueKey('shell-connection-indicator'));
    expect(indicator, findsOneWidget);
    expect(_textInside(const ValueKey('shell-connection-indicator')), findsNothing);
    // The dot still has a tooltip, so its meaning is not lost below 920 px.
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: indicator, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the connection indicator opens Settings on Diagnostics', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container, width: 1920);

    expect(container.read(showSettingsProvider), isFalse);
    await tester.tap(find.byKey(const ValueKey('shell-connection-indicator')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(container.read(showSettingsProvider), isTrue);
    // Settings opens by section id, so the test does not depend on tab order.
    expect(
      tester.widget<SettingsView>(find.byType(SettingsView)).initialSection,
      kSettingsSectionDiagnostics,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings button tooltip carries the Ctrl/Cmd+, shortcut', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container, width: 1920);

    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('Ctrl / Cmd + ,'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('shell-title-divider')), findsOneWidget);
  });
}

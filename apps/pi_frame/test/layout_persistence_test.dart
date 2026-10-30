import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/layout/layout_store.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => 'session_1'),
    connectionStateProvider.overrideWith(
      (ref) => Stream.value(DaemonConnectionState.connected),
    ),
    sessionStateFamily('session_1').overrideWith(
      (ref) => SessionStateNotifier('session_1', null)
        ..state = const SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1')
        .overrideWith((ref) => RepositoryController('session_1', () => null)),
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
    await tester.pumpAndSettle();
  }

  testWidgets('a hidden repository pane stays hidden after restart', (
    tester,
  ) async {
    layoutFile.writeAsStringSync(
      jsonEncode({
        'visibility': {'repository': false, 'chat': true, 'git': true},
        'sidebarCollapsed': false,
      }),
    );
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    expect(find.byTooltip('Collassa pannello Repository'), findsNothing);
    expect(find.byTooltip('Espandi pannello Repository'), findsNothing);
    expect(find.byTooltip('Collassa pannello Git Changes'), findsOneWidget);
  });

  testWidgets('hiding a pane and collapsing the sessions bar are saved', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    await tester.tap(find.byTooltip('Collassa barra sessioni'));
    await tester.pumpAndSettle();

    final saved =
        jsonDecode(layoutFile.readAsStringSync()) as Map<String, dynamic>;
    expect(saved['sidebarCollapsed'], isTrue);
    expect((saved['visibility'] as Map)['repository'], isTrue);
  });

  testWidgets('a corrupt layout file falls back to the default layout', (
    tester,
  ) async {
    layoutFile.writeAsStringSync('{not json');
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    expect(find.byTooltip('Collassa pannello Repository'), findsOneWidget);
    expect(find.byTooltip('Collassa barra sessioni'), findsOneWidget);
  });

  test('no file is written when storage is disabled under tests', () {
    LayoutStore.instance.setStorageFileForTesting(null);
    expect(
      () => LayoutStore.instance.save({'sidebarCollapsed': true}),
      returnsNormally,
    );
    expect(LayoutStore.instance.load(), isEmpty);
  });
}

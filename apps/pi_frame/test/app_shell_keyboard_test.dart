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
      (ref) =>
          SessionStateNotifier('session_1', null)
            ..state = SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1')
        .overrideWith((ref) => RepositoryController('session_1', () => null)),
  ],
);

/// The shell region ([FocusRegion] name) that holds [node], or null outside the shell.
String? _regionOf(FocusNode? node) {
  String? found;
  node?.context?.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value.startsWith('focus-region-')) {
      found = key.value.substring('focus-region-'.length);
      return false;
    }
    // A pane divider sits between two regions in Tab order.
    if (key is ValueKey<String> && key.value.startsWith('pane-divider-')) {
      found = 'divider';
      return false;
    }
    return true;
  });
  return found;
}

FocusNode? get _primary => FocusManager.instance.primaryFocus;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_keyboard_test_');
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
    // Bounded pumps: a disconnected client keeps an indicator animating forever.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Focuses the composer input, as a user would.
  Future<void> focusComposer(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('focus-region-composer')),
            matching: find.byType(EditableText),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(_regionOf(_primary), 'composer');
  }

  Future<void> sendKey(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
    bool shift = false,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Tab from the composer visits the regions in order', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    await focusComposer(tester);

    final visited = <String>[];
    for (var i = 0; i < 80 && visited.length < 9; i++) {
      await sendKey(tester, LogicalKeyboardKey.tab);
      final region = _regionOf(_primary) ?? 'outside';
      if (visited.isEmpty || visited.last != region) visited.add(region);
      if (visited.length > 1 && visited.last == 'composer') break;
    }

    // The composer is followed by the divider before the companion pane, then the wrap
    // to the title bar, down the panes in order, and back to the composer. The dividers
    // between panes are Tab stops in their place.
    expect(visited, [
      'composer',
      'divider',
      'companion',
      'titleBar',
      'sessions',
      'repository',
      'divider',
      'transcript',
      'composer',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F6 and Shift+F6 move between panes', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    await focusComposer(tester);

    await sendKey(tester, LogicalKeyboardKey.f6);
    expect(_regionOf(_primary), 'companion');

    await sendKey(tester, LogicalKeyboardKey.f6);
    expect(_regionOf(_primary), 'titleBar');

    await sendKey(tester, LogicalKeyboardKey.f6, shift: true);
    expect(_regionOf(_primary), 'companion');

    await sendKey(tester, LogicalKeyboardKey.f6, shift: true);
    expect(_regionOf(_primary), 'composer');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ctrl+1 to Ctrl+4 focus sessions, repository, chat and companion',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await pumpShell(tester, container);

      final expected = <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.digit1: 'sessions',
        LogicalKeyboardKey.digit2: 'repository',
        LogicalKeyboardKey.digit3: 'composer',
        LogicalKeyboardKey.digit4: 'companion',
      };
      for (final entry in expected.entries) {
        await sendKey(
          tester,
          entry.key,
          modifier: LogicalKeyboardKey.controlLeft,
        );
        expect(_regionOf(_primary), entry.value, reason: 'after ${entry.key}');
      }
      expect(tester.takeException(), isNull);
    },
  );
}

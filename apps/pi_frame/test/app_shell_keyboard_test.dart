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
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/session_changes/session_changes_provider.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

/// Records the commands sent to the daemon, so a test can tell whether Escape interrupted.
class _InterruptRecordingClient extends PcpClient {
  _InterruptRecordingClient() : super(port: 1, token: 'test');

  final List<String> commandTypes = [];

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async {
    commandTypes.add(command.type);
    if (command.type == 'agent.interrupt') {
      return {
        'data': {
          'interrupted': true,
          'queue': {'steering': <String>[], 'followUp': <String>[]},
        },
      };
    }
    return {'data': <String, dynamic>{}};
  }
}

/// A session that is streaming a run, so Escape has something to interrupt.
ProviderContainer _streamingContainer(PcpClient client) {
  final notifier = SessionStateNotifier('session_1', client)
    ..state = SessionState(
      sessionId: 'session_1',
      cwd: 'C:/repo',
      agentStatus: AgentStatus.working,
      streamingTextBlocks: const {0: 'Generating...'},
      // A queued steer keeps the composer expanded, so its input can take focus.
      steeringQueue: const ['Queued steer'],
    );
  return ProviderContainer(
    overrides: [
      desktopWindowLifecycleProvider.overrideWithValue(false),
      desktopChromeProvider.overrideWithValue(false),
      pcpClientProvider.overrideWithValue(client),
      activeSessionIdProvider.overrideWith((ref) => 'session_1'),
      connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
      sessionListProvider.overrideWith((ref) async => const []),
      sessionStateFamily('session_1').overrideWith((ref) => notifier),
      repositoryStateProvider('session_1').overrideWith((ref) => RepositoryController('session_1', () => null)),
    ],
  );
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    desktopWindowLifecycleProvider.overrideWithValue(false),
    desktopChromeProvider.overrideWithValue(false),
    activeSessionIdProvider.overrideWith((ref) => 'session_1'),
    connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
    sessionListProvider.overrideWith((ref) async => const []),
    sessionStateFamily('session_1').overrideWith(
      (ref) => SessionStateNotifier('session_1', null)..state = SessionState(sessionId: 'session_1', cwd: 'C:/repo'),
    ),
    repositoryStateProvider('session_1').overrideWith((ref) => RepositoryController('session_1', () => null)),
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
    LayoutStore.instance.setStorageFileForTesting(File('${tempDir.path}/layout.json'));
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
    // Bounded pumps: a disconnected client keeps an indicator animating forever.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Focuses the composer input, as a user would.
  Future<void> focusComposer(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(of: find.byKey(const ValueKey('focus-region-composer')), matching: find.byType(EditableText))
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

  ScaffoldState scaffold(WidgetTester tester) => tester.state<ScaffoldState>(find.byType(Scaffold).first);

  testWidgets('Tab from the composer visits the regions in order', (tester) async {
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

  testWidgets('Ctrl+1 to Ctrl+4 focus sessions, repository, chat and companion', (tester) async {
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
      await sendKey(tester, entry.key, modifier: LogicalKeyboardKey.controlLeft);
      expect(_regionOf(_primary), entry.value, reason: 'after ${entry.key}');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the end drawer, then Review mode, then does nothing', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    await tester.tap(find.byKey(const ValueKey('shell-context-drawer-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isTrue);

    container.read(isReviewingChangesProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 500));

    // The end drawer is the higher layer: it closes first, Review mode stays open.
    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isFalse);
    expect(container.read(isReviewingChangesProvider), isTrue);

    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(isReviewingChangesProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the end drawer has no shell heading and closes on Escape or a scrim tap', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    await tester.tap(find.byKey(const ValueKey('shell-context-drawer-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isTrue);
    // The shell no longer draws its own "Area di lavoro" heading or close button.
    expect(find.text('Area di lavoro'), findsNothing);
    expect(find.byTooltip('Chiudi workspace'), findsNothing);

    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isFalse);

    await tester.tap(find.byKey(const ValueKey('shell-context-drawer-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isTrue);

    // A tap on the scrim, left of the drawer, closes it.
    await tester.tapAt(const Offset(100, 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes Settings', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await pumpShell(tester, container);

    container.read(showSettingsProvider.notifier).state = true;
    await tester.pump(const Duration(milliseconds: 500));

    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(showSettingsProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape interrupts a streaming run only when the composer is focused and no layer is open', (
    tester,
  ) async {
    final client = _InterruptRecordingClient();
    final container = _streamingContainer(client);
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    await focusComposer(tester);
    expect(client.commandTypes, isNot(contains('agent.interrupt')));

    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.commandTypes, contains('agent.interrupt'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the end drawer open, Escape closes the drawer and does not interrupt', (tester) async {
    final client = _InterruptRecordingClient();
    final container = _streamingContainer(client);
    addTearDown(container.dispose);
    await pumpShell(tester, container);
    await focusComposer(tester);

    scaffold(tester).openEndDrawer();
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isTrue);
    // Opening the drawer moves focus away from the composer. Return focus to the composer
    // while the drawer stays open, so Escape reaches the composer with a layer open.
    final input = tester.state<EditableTextState>(
      find
          .descendant(of: find.byKey(const ValueKey('focus-region-composer')), matching: find.byType(EditableText))
          .first,
    );
    input.widget.focusNode.requestFocus();
    await tester.pump();
    expect(_regionOf(_primary), 'composer');

    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaffold(tester).isEndDrawerOpen, isFalse);
    expect(client.commandTypes, isNot(contains('agent.interrupt')));

    // With nothing open, the same key interrupts.
    await sendKey(tester, LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.commandTypes, contains('agent.interrupt'));
    expect(tester.takeException(), isNull);
  });
}

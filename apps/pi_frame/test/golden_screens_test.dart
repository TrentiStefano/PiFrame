// Golden tests for five key screens (welcome, workspace with a transcript, composer with the slash menu open, composer
// with a staged command chip, settings), each in light and dark at 1920x1032 logical pixels: ten references. They run
// only in `verify`, on Windows, through `pnpm run goldens:update` (regenerate) or the golden step of the gate (compare).
// See docs/pr-verification.md.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/settings/diagnostics.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'support/capture_support.dart';

/// The window the screens are rendered in: a full-screen window with the taskbar, at device pixel ratio 1.
const _screenSize = Size(1920, 1032);

/// Longer than the slowest one-shot timer a settings screen starts (the 10 s package-load hint).
const _settleTimers = Duration(seconds: 15);

/// Where Flutter writes the masterImage, testImage and isolatedDiff of a failing comparison (basedir/failures).
/// Ignored by git and cleared at the start of every run.
final _failuresDir = Directory('test/failures');

// Synthetic data is confined to tests; the product never displays demo sessions. English only, like the app's copy.
const _sampleSession = SessionState(
  sessionId: 'design-session',
  sessionName: 'Make reconnection reliable',
  cwd: 'C:/Projects/pi-frame',
  currentModel: 'claude-sonnet',
  currentThinkingLevel: 'medium',
  sessionStats: {
    'cost': 0.42,
    'tokens': {'total': 42000},
    'contextUsage': {'tokens': 70656, 'contextWindow': 128000, 'percent': 55.2},
  },
  extensionStatuses: {'caveman': 'full', 'ponytail': 'full'},
  entries: [
    SessionEntry(
      id: 'u1',
      role: 'user',
      timestamp: 1,
      text: 'Check the reconnect flow. I want to keep the history and recover events without duplicates.',
    ),
    SessionEntry(
      id: 'a1',
      role: 'assistant',
      timestamp: 2,
      thinking: 'Check the journal and the event order before changing the client.',
      toolCalls: [
        ToolExecutionState(
          toolCallId: 't1',
          toolName: 'read',
          args: {'path': 'lib/data/daemon/pcp_client.dart'},
          output: 'Replay cursor verified. No duplicate events.',
          durationMs: 42,
        ),
      ],
      text: 'The client keeps the replay cursor. We can isolate the reconnect path without changing session ownership.\n\n```dart\nfinal cursor = session.lastAppliedSeq;\nawait client.attach(sessionId);\n```\n\nPi keeps the history. The next step is to verify the behaviour with a disconnect during streaming.',
    ),
  ],
);

/// The slash commands the composer offers; the same fake commands as composer_command_chip_test.
const _commands = [
  {'name': 'reload', 'description': 'Reload Pi resources', 'source': 'builtin'},
  {'name': 'caveman', 'description': 'Terse mode', 'argumentHint': '[level]', 'source': 'extension'},
  {'name': 'review', 'description': 'Code review template', 'source': 'prompt'},
];

const _sessions = [
  {
    'id': 'design-session',
    'name': 'Make reconnection reliable',
    'cwd': 'C:/Projects/pi-frame',
    'isActive': true,
    'lastMessagePreview': 'Verify the journal and replay',
  },
  {
    'id': 's2',
    'name': 'Simplify the composer',
    'cwd': 'C:/Projects/pi-frame',
    'isActive': false,
    'lastMessagePreview': 'Queued instructions handling',
  },
  {
    'id': 's3',
    'name': 'Explore the PCP protocol',
    'cwd': 'C:/Projects/pcp',
    'isActive': false,
    'lastMessagePreview': 'Contracts and generated types',
  },
];

/// A session whose slash commands are the fixture's, so the composer's menu opens without a daemon.
class _GoldenSession extends SessionStateNotifier {
  _GoldenSession(SessionState initial) : super(initial.sessionId, null) {
    state = initial;
  }

  @override
  Future<List<Map<String, dynamic>>> getCommands() async => _commands;
}

/// The repository and Git panes read the fixture workspace instead of a daemon (as in redesign_layout_test).
class _GoldenWorkspaceClient extends PcpClient {
  _GoldenWorkspaceClient() : super(port: 1, token: 'fixture');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': 'C:/Projects/pi-frame',
      'truncated': false,
      'files': [
        {'path': 'apps/pi_frame/lib/app/app_shell.dart', 'sizeBytes': 4800},
        {'path': 'apps/pi_frame/lib/features/workspace/repository_workspace.dart', 'sizeBytes': 7200},
      ],
    },
  };

  /// The settings page asks for the Pi package list; an empty list keeps its slow-load timer from starting.
  @override
  Future<Map<String, dynamic>> listPiPackages({bool checkUpdates = false}) async => {
    'data': {'packages': <Map<String, dynamic>>[]},
  };

  @override
  Future<Map<String, dynamic>> refreshWorkspace(String sessionId, {String? cwd}) async => {
    'data': {
      'isRepository': true,
      'rootPath': 'C:/Projects/pi-frame',
      'branch': 'fix/pi-session-workflows',
      'files': [
        {
          'path': 'apps/pi_frame/lib/app/app_shell.dart',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
          'additions': 8,
          'deletions': 2,
        },
        {
          'path': 'apps/pi_frame/lib/features/workspace/repository_workspace.dart',
          'status': 'modified',
          'staged': true,
          'unstaged': false,
          'additions': 40,
          'deletions': 4,
        },
      ],
      'totalAdditions': 48,
      'totalDeletions': 6,
    },
  };
}

/// Expected, actual and diff images go to test/failures; the failure names the screen and the update command.
class _ScreenGoldenComparator extends LocalFileComparator {
  _ScreenGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    try {
      return await super.compare(imageBytes, golden);
    } on FlutterError catch (error) {
      throw FlutterError(
        'Golden screen "${_screenName(golden)}" differs from its reference (${golden.pathSegments.last}).\n'
        '${error.message}\n'
        'Expected, actual and diff images are in ${_failuresDir.path}/. '
        'If the change is intended, regenerate the references with: pnpm run goldens:update',
      );
    }
  }
}

/// `goldens/workspace_dark.png` -> `workspace (dark)`.
String _screenName(Uri golden) {
  final stem = golden.pathSegments.last.replaceAll('.png', '');
  final separator = stem.lastIndexOf('_');
  return '${stem.substring(0, separator)} (${stem.substring(separator + 1)})';
}

/// Pumps the whole app for [session] (none: the welcome screen) and returns the key of the boundary to capture.
Future<GlobalKey> _pumpApp(WidgetTester tester, {required bool dark, required SessionState? session}) async {
  tester.view.physicalSize = _screenSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final themeName = dark ? 'piframe-dark' : 'piframe-light';
  final repo = ThemeRepository()
    ..registerThemeJson(File('assets/themes/$themeName.json').readAsStringSync())
    ..setActiveTheme(themeName);
  addTearDown(repo.dispose);
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        diagnosticsFixtureLabelProvider.overrideWithValue('SYNTHETIC DATA · GOLDEN'),
        themeRepositoryProvider.overrideWithValue(repo),
        daemonEndpointProvider.overrideWith((ref) async => null),
        pcpClientProvider.overrideWithValue(_GoldenWorkspaceClient()),
        connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
        sessionListProvider.overrideWith((ref) async => _sessions),
        activeSessionIdProvider.overrideWith((ref) => session?.sessionId),
        if (session != null) sessionStateFamily(session.sessionId).overrideWith((ref) => _GoldenSession(session)),
      ],
      child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: repo.activeTheme.toThemeData(),
          home: const AppShell(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boundaryKey;
}

/// Registers one golden per theme. [body] arranges the screen, asserts its content and returns the boundary to capture.
void _goldenTests(String screen, Future<GlobalKey> Function(WidgetTester tester, {required bool dark}) body) {
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets(
      'golden: $screen ($theme)',
      (tester) async {
        final boundaryKey = await body(tester, dark: dark);
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(boundaryKey), matchesGoldenFile('goldens/${screen}_$theme.png'));
        // Let every timer the screen started (tooltips, slow-load hints) fire, then dispose the app: a timer still
        // pending after disposal fails the test.
        await tester.pump(_settleTimers);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      tags: const ['golden'],
      skip: !Platform.isWindows,
    );
  }
}

void main() {
  setUpAll(() async {
    if (_failuresDir.existsSync()) _failuresDir.deleteSync(recursive: true);
    goldenFileComparator = _ScreenGoldenComparator(Uri.file('${Directory.current.path}/test/golden_screens_test.dart'));
    if (!Platform.isWindows) {
      debugPrint(
        'Golden screens are compared on Windows only. Run them there with `pnpm run goldens:update` or `pnpm run verify`.',
      );
      return;
    }
    await loadAppFonts();
  });

  _goldenTests('welcome', (tester, {required bool dark}) async {
    final key = await _pumpApp(tester, dark: dark, session: null);
    expect(find.text('Resume your work'), findsOneWidget);
    return key;
  });

  _goldenTests('workspace', (tester, {required bool dark}) async {
    final key = await _pumpApp(tester, dark: dark, session: _sampleSession);
    expect(find.textContaining('claude-sonnet', findRichText: true), findsOneWidget);
    return key;
  });

  // Two composer states: the slash menu open, and a staged command chip with the menu closed. They never show together:
  // a chip is the active command, and the menu only opens without one (composer_command_chip_test covers the behaviour).
  _goldenTests('composer-menu', (tester, {required bool dark}) async {
    final key = await _pumpApp(tester, dark: dark, session: _sampleSession);
    final field = find.descendant(of: find.byType(Composer), matching: find.byType(TextField));
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '/');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-slash-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-command-chip')), findsNothing);
    return key;
  });

  _goldenTests('composer-chip', (tester, {required bool dark}) async {
    final key = await _pumpApp(tester, dark: dark, session: _sampleSession);
    final field = find.descendant(of: find.byType(Composer), matching: find.byType(TextField));
    await tester.tap(field);
    await tester.pumpAndSettle();
    // Enter on a filtered menu item stages it as a chip; the menu closes.
    await tester.enterText(field, '/rel');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-command-chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-slash-menu')), findsNothing);
    return key;
  });

  _goldenTests('settings', (tester, {required bool dark}) async {
    final key = await _pumpApp(tester, dark: dark, session: _sampleSession);
    await tester.tap(find.byTooltip('Settings (Ctrl / Cmd + ,)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);
    return key;
  });
}

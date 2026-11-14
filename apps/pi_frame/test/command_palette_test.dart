import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/command_palette/command_palette.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';

class _Host extends ConsumerWidget {
  final void Function(BuildContext context)? onSettings;
  final bool Function(WorkspacePane pane)? isPaneVisible;
  final void Function(WorkspacePane pane)? onTogglePane;

  const _Host({this.onSettings, this.isPaneVisible, this.onTogglePane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('open-palette'),
          onPressed: () => CommandPalette.show(
            context,
            ref: ref,
            onOpenSettings: onSettings == null
                ? null
                : () => onSettings!(context),
            isPaneVisible: isPaneVisible,
            onTogglePane: onTogglePane,
          ),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Widget _wrap({
  required Widget child,
  String? activeSessionId,
  AgentStatus agentStatus = AgentStatus.idle,
}) {
  return ProviderScope(
    overrides: [
      appLanguageProvider.overrideWith(
        (ref) => AppLanguageNotifier()..setLanguage(AppLanguage.en),
      ),
      pcpClientProvider.overrideWithValue(null),
      activeSessionIdProvider.overrideWith((ref) => activeSessionId),
      sessionListProvider.overrideWith(
        (ref) async => [
          {'id': 's1', 'name': 'Workspace planning', 'cwd': '/work/a'},
          {'id': 's2', 'name': 'Second repo review', 'cwd': '/work/b'},
        ],
      ),
      sessionStateFamily('session-a').overrideWith(
        (ref) => SessionStateNotifier('session-a', null)
          ..state = SessionState(
            sessionId: 'session-a',
            cwd: '/repo',
            agentStatus: agentStatus,
          ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [FrameTokens.light]),
      home: child,
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-palette')));
  await tester.pumpAndSettle();
}

/// The palette caps its list at 60% of the window, and rows build lazily, so
/// tests that reach later rows need a taller window.
void _paletteTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await body(tester);
  });
}

void main() {
  group('CommandPalette', () {
    _paletteTest('shortcut key caps are separate from titles', (tester) async {
      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          child: const _Host(),
        ),
      );
      await _open(tester);

      final keys = find.byKey(
        const ValueKey('palette-keys-toggle_side_panel'),
      );
      expect(keys, findsOneWidget);
      expect(
        find.descendant(of: keys, matching: find.text('Ctrl')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: keys, matching: find.text('Shift')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: keys, matching: find.text('B')),
        findsOneWidget,
      );
      // Key caps use the type scale, never below the 11 px floor.
      final capText = tester.widget<Text>(
        find.descendant(of: keys, matching: find.text('Ctrl')),
      );
      expect(capText.style?.fontSize, greaterThanOrEqualTo(11));
      // The title no longer carries the shortcut.
      expect(find.text('Side conversation'), findsOneWidget);
      expect(find.textContaining('Ctrl+'), findsNothing);
      expect(find.textContaining('(Esc)'), findsNothing);
    });

    _paletteTest('platform-aware modifier label uses Command on macOS', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          child: const _Host(),
        ),
      );
      await _open(tester);

      final keys = find.byKey(
        const ValueKey('palette-keys-toggle_side_panel'),
      );
      expect(
        find.descendant(of: keys, matching: find.text('⌘')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: keys, matching: find.text('⇧')),
        findsOneWidget,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    _paletteTest('interrupt is hidden when nothing runs', (tester) async {
      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          child: const _Host(),
        ),
      );
      await _open(tester);

      expect(find.text('Interrupt agent'), findsNothing);
      expect(find.byKey(const ValueKey('palette-action-interrupt')), findsNothing);
    });

    _paletteTest('interrupt is offered while the agent is working', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          agentStatus: AgentStatus.working,
          child: const _Host(),
        ),
      );
      await _open(tester);

      expect(find.text('Interrupt agent'), findsOneWidget);
      expect(find.textContaining('(Esc)'), findsNothing);
    });

    _paletteTest('session commands are hidden without an active session', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(child: const _Host()));
      await _open(tester);

      expect(find.byKey(const ValueKey('palette-action-compact')), findsNothing);
      expect(
        find.byKey(const ValueKey('palette-action-toggle_side_panel')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('palette-action-git_fetch')), findsNothing);
      expect(
        find.byKey(const ValueKey('palette-action-review_changes')),
        findsNothing,
      );
      // Always-available commands remain.
      expect(
        find.byKey(const ValueKey('palette-action-go_to_session')),
        findsOneWidget,
      );
    });

    _paletteTest('commands are grouped under headers', (tester) async {
      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          child: _Host(onSettings: (_) {}),
        ),
      );
      await _open(tester);

      expect(find.text('SESSION'), findsOneWidget);
      expect(find.text('VIEW'), findsOneWidget);
      expect(find.text('GIT'), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);
    });

    _paletteTest('a query switches to a flat list without group headers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          child: const _Host(),
        ),
      );
      await _open(tester);

      await tester.enterText(
        find.byKey(const ValueKey('command-palette-search-field')),
        'fetch',
      );
      await tester.pump();

      expect(find.text('GIT'), findsNothing);
      expect(
        find.byKey(const ValueKey('palette-action-git_fetch')),
        findsOneWidget,
      );
    });

    _paletteTest('palette closes before the command runs', (tester) async {
      var settingsCalls = 0;
      await tester.pumpWidget(
        _wrap(
          child: _Host(
            onSettings: (context) {
              settingsCalls++;
              showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  content: Text('Stacked dialog'),
                ),
              );
            },
          ),
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(const ValueKey('palette-action-settings')));
      await tester.pumpAndSettle();

      expect(settingsCalls, 1);
      expect(find.text('Stacked dialog'), findsOneWidget);
      // The palette route is gone; only the command's dialog remains.
      expect(
        find.byKey(const ValueKey('command-palette-search-field')),
        findsNothing,
      );
    });

    _paletteTest('pane commands show or hide each pane', (tester) async {
      final toggled = <WorkspacePane>[];
      await tester.pumpWidget(
        _wrap(
          child: _Host(
            isPaneVisible: (pane) => pane != WorkspacePane.repository,
            onTogglePane: toggled.add,
          ),
        ),
      );
      await _open(tester);

      expect(find.text('Show Repository'), findsOneWidget);
      expect(find.text('Hide Chat'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('palette-action-pane_repository')),
      );
      await tester.pumpAndSettle();

      expect(toggled, [WorkspacePane.repository]);
      expect(
        find.byKey(const ValueKey('command-palette-search-field')),
        findsNothing,
      );
    });

    _paletteTest('last visible pane cannot be hidden from the palette', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          child: _Host(
            isPaneVisible: (pane) => pane == WorkspacePane.chat,
            onTogglePane: (_) {},
          ),
        ),
      );
      await _open(tester);

      expect(find.text('Hide Chat'), findsNothing);
      expect(find.text('Show Repository'), findsOneWidget);
    });

    _paletteTest('go to session fuzzy-searches the session list', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(child: const _Host()));
      await _open(tester);

      await tester.tap(
        find.byKey(const ValueKey('palette-action-go_to_session')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search sessions...'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('palette-action-session_s1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('palette-action-session_s2')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('command-palette-search-field')),
        'wsp',
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('palette-action-session_s1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('palette-action-session_s2')),
        findsNothing,
      );
    });

    _paletteTest('list is sized to content and capped at 60 percent of window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          activeSessionId: 'session-a',
          child: _Host(onSettings: (_) {}),
        ),
      );
      await _open(tester);

      final list = find.byKey(const ValueKey('command-palette-list'));
      expect(tester.getSize(list).height, lessThanOrEqualTo(600 * 0.6));

      await tester.enterText(
        find.byKey(const ValueKey('command-palette-search-field')),
        'settings',
      );
      await tester.pump();

      expect(tester.getSize(list).height, lessThan(120));
    });
  });
}

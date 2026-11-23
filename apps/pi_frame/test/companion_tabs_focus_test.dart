import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/session_changes/session_changes_pane.dart';
import 'package:pi_frame/features/session_changes/session_changes_provider.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _FixedSessionChangesNotifier extends StateNotifier<SessionChangesState> implements SessionChangesNotifier {
  _FixedSessionChangesNotifier() : super(const SessionChangesState());

  @override
  late final Ref ref;

  @override
  String get sessionId => 'session_1';

  @override
  Future<void> refresh({bool joinRunning = false}) async {}

  @override
  Future<void> fetchFileDiff(String filePath) async {}
}

/// Companion tabs of the Review pane (plan task 6.1): focusable, announced as selected
/// buttons, and ←/→ or Enter select the tab.
void main() {
  const tabs = [WorkspacePane.repository, WorkspacePane.git, WorkspacePane.chat];

  Future<List<WorkspacePane>> pumpPane(
    WidgetTester tester, {
    required List<WorkspacePane> selected,
    double width = 1600,
  }) async {
    selected.clear();
    // The test surface defaults to 800 px, which would clamp the pane below.
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionChangesProvider('session_1').overrideWith((ref) => _FixedSessionChangesNotifier())],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: SessionChangesPane(
                sessionId: 'session_1',
                companionTabs: tabs,
                activeCompanionTab: WorkspacePane.git,
                onSelectCompanionTab: selected.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return selected;
  }

  /// The companion tab that holds primary focus, or null.
  WorkspacePane? focusedTab() {
    final label = FocusManager.instance.primaryFocus?.debugLabel ?? '';
    for (final tab in tabs) {
      if (label == 'companion-tab-${tab.name}') return tab;
    }
    return null;
  }

  // The app defaults to Italian, so the tab names are the Italian strings.
  testWidgets('tabs are selected buttons in the semantics tree', (tester) async {
    final semantics = tester.ensureSemantics();
    final selected = <WorkspacePane>[];
    await pumpPane(tester, selected: selected);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Review Changes')),
      matchesSemantics(label: 'Review Changes', isButton: true, hasSelectedState: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('File')),
      matchesSemantics(label: 'File', isButton: true, hasSelectedState: true, isSelected: false),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Tab reaches every companion tab', (tester) async {
    final selected = <WorkspacePane>[];
    await pumpPane(tester, selected: selected);

    final reached = <WorkspacePane>{};
    for (var i = 0; i < 60 && reached.length < tabs.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final tab = focusedTab();
      if (tab != null) reached.add(tab);
    }
    expect(reached, containsAll(tabs));
    expect(tester.takeException(), isNull);
  });

  testWidgets('←/→ select the neighbouring tab and move focus to it', (tester) async {
    final selected = <WorkspacePane>[];
    await pumpPane(tester, selected: selected);

    // Reach the repository tab with Tab, then step right and left.
    for (var i = 0; i < 60 && focusedTab() != WorkspacePane.repository; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedTab(), WorkspacePane.repository);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selected, [WorkspacePane.git]);
    expect(focusedTab(), WorkspacePane.git);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(selected.last, WorkspacePane.repository);
    expect(focusedTab(), WorkspacePane.repository);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter selects the focused companion tab', (tester) async {
    final selected = <WorkspacePane>[];
    await pumpPane(tester, selected: selected);

    for (var i = 0; i < 60 && focusedTab() != WorkspacePane.chat; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedTab(), WorkspacePane.chat);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, [WorkspacePane.chat]);
    expect(tester.takeException(), isNull);
  });

  // No overflow exception is ignored: every width must lay out cleanly.
  for (final width in [1600.0, 320.0]) {
    testWidgets('tab header lays out without overflow at ${width.toInt()} px', (tester) async {
      final semantics = tester.ensureSemantics();
      final selected = <WorkspacePane>[];
      await pumpPane(tester, selected: selected, width: width);

      // Every tab keeps its name for assistive tech, even when only its icon shows.
      for (final label in ['File', 'Review Changes', 'Chat']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      // The active tab always shows its label; at 320 px the others are icon-only.
      expect(find.text('REVIEW CHANGES'), findsOneWidget);
      if (width < kCompanionTabLabelsMinWidth) {
        expect(find.text('File'), findsNothing);
        expect(find.text('Chat'), findsNothing);
      } else {
        expect(find.text('File'), findsOneWidget);
        expect(find.text('Chat'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

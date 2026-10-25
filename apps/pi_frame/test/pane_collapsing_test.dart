import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';

void main() {
  testWidgets('Panes can collapse and expand using arrow icons', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        desktopWindowLifecycleProvider.overrideWithValue(false),
        desktopChromeProvider.overrideWithValue(false),
        activeSessionIdProvider.overrideWith((ref) => 'session_1'),
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(DaemonConnectionState.connected),
        ),
        sessionStateFamily('session_1').overrideWith(
          (ref) => SessionStateNotifier('session_1', null)
            ..state = const SessionState(
              sessionId: 'session_1',
              cwd: 'C:/repo',
            ),
        ),
        repositoryStateProvider('session_1').overrideWith(
          (ref) => RepositoryController('session_1', () => null),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Repository pane collapse button exists
    final repoCollapseBtn = find.byTooltip('Collassa pannello Repository');
    expect(repoCollapseBtn, findsOneWidget);

    // Click collapse button on Repository pane
    await tester.tap(repoCollapseBtn);
    await tester.pumpAndSettle();

    // Now collapsed strip for Repository should be visible
    expect(find.text('REPOSITORY'), findsOneWidget);
    final repoExpandBtn = find.byTooltip('Espandi pannello Repository');
    expect(repoExpandBtn, findsOneWidget);

    // Tap expand button to restore Repository pane
    await tester.tap(repoExpandBtn);
    await tester.pumpAndSettle();

    // Repository pane is expanded again
    expect(find.byTooltip('Collassa pannello Repository'), findsOneWidget);

    // Verify Git Changes pane collapse button exists
    final gitCollapseBtn = find.byTooltip('Collassa pannello Git Changes');
    expect(gitCollapseBtn, findsOneWidget);

    // Click collapse button on Git Changes pane
    await tester.tap(gitCollapseBtn);
    await tester.pumpAndSettle();

    // Collapsed strip for Git Changes should be visible
    expect(find.text('GIT CHANGES'), findsOneWidget);
    final gitExpandBtn = find.byTooltip('Espandi pannello Git Changes');
    expect(gitExpandBtn, findsOneWidget);

    // Tap expand button to restore Git Changes pane
    await tester.tap(gitExpandBtn);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collassa pannello Git Changes'), findsOneWidget);
  });

  testWidgets('Sessions sidebar can collapse and expand using arrow icon', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        desktopWindowLifecycleProvider.overrideWithValue(false),
        desktopChromeProvider.overrideWithValue(false),
        activeSessionIdProvider.overrideWith((ref) => 'session_1'),
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(DaemonConnectionState.connected),
        ),
        sessionStateFamily('session_1').overrideWith(
          (ref) => SessionStateNotifier('session_1', null)
            ..state = const SessionState(
              sessionId: 'session_1',
              cwd: 'C:/repo',
            ),
        ),
        repositoryStateProvider('session_1').overrideWith(
          (ref) => RepositoryController('session_1', () => null),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Sessions sidebar collapse button exists
    final sidebarCollapseBtn = find.byTooltip('Collassa barra sessioni');
    expect(sidebarCollapseBtn, findsOneWidget);

    // Tap collapse button
    await tester.tap(sidebarCollapseBtn);
    await tester.pumpAndSettle();

    // Verify collapsed sidebar strip exists
    final sidebarExpandBtn = find.byTooltip('Espandi barra sessioni');
    expect(sidebarExpandBtn, findsOneWidget);

    // Tap expand button
    await tester.tap(sidebarExpandBtn);
    await tester.pumpAndSettle();

    // Expanded sidebar is back
    expect(find.byTooltip('Collassa barra sessioni'), findsOneWidget);
  });

  testWidgets('Pane collapses when dragging border over minimum space', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        desktopWindowLifecycleProvider.overrideWithValue(false),
        desktopChromeProvider.overrideWithValue(false),
        activeSessionIdProvider.overrideWith((ref) => 'session_1'),
        connectionStateProvider.overrideWith(
          (ref) => Stream.value(DaemonConnectionState.connected),
        ),
        sessionStateFamily('session_1').overrideWith(
          (ref) => SessionStateNotifier('session_1', null)
            ..state = const SessionState(
              sessionId: 'session_1',
              cwd: 'C:/repo',
            ),
        ),
        repositoryStateProvider('session_1').overrideWith(
          (ref) => RepositoryController('session_1', () => null),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the divider between repository and chat
    final dividerFinder = find.byKey(
      const ValueKey('pane-divider-WorkspacePane.repository-WorkspacePane.chat'),
    );
    expect(dividerFinder, findsOneWidget);

    // Drag the divider far to the left (past the minimum space)
    await tester.drag(dividerFinder, const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Repository should now be collapsed!
    expect(find.text('REPOSITORY'), findsOneWidget);
    expect(find.byTooltip('Espandi pannello Repository'), findsOneWidget);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/changelog/changelog_models.dart';
import 'package:pi_frame/data/changelog/changelog_service.dart';
import 'package:pi_frame/data/changelog/changelog_store.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/data/platform/link_service.dart';
import 'package:pi_frame/features/changelog/changelog_dialog.dart';
import 'package:pi_frame/features/changelog/startup_changelog_watcher.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'support/fake_platform_services.dart';

void main() {
  Widget buildTestDialog({required ChangelogRelease release, List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(body: ChangelogDialog(release: release)),
      ),
    );
  }

  testWidgets('renders features, bug fixes, scopes and close button', (tester) async {
    const release = ChangelogRelease(
      version: '1.5.0',
      date: '2026-11-20',
      features: [
        ChangelogItem(
          scope: 'chat',
          message: 'add read-only side conversations',
          commitHash: '2e48ed2',
          commitUrl: 'https://github.com/test/commit/2e48ed2',
          isFeature: true,
        ),
      ],
      fixes: [
        ChangelogItem(
          scope: 'workspace',
          message: 'do not collapse git changes when opening agents sidecar',
          isFeature: false,
        ),
      ],
    );

    await tester.pumpWidget(buildTestDialog(release: release));
    await tester.pumpAndSettle();

    // Verify title and date
    expect(find.textContaining('1.5.0'), findsOneWidget);
    expect(find.text('2026-11-20'), findsOneWidget);

    // Verify sections and item texts
    expect(find.textContaining('New Features'), findsOneWidget);
    expect(find.text('chat'), findsOneWidget);
    expect(find.text('add read-only side conversations'), findsOneWidget);
    expect(find.text('2e48ed2'), findsOneWidget);

    expect(find.textContaining('Bug Fixes'), findsOneWidget);
    expect(find.text('workspace'), findsOneWidget);
    expect(find.text('do not collapse git changes when opening agents sidecar'), findsOneWidget);

    // Close button
    expect(find.byKey(const ValueKey('changelog-dialog-close-btn')), findsOneWidget);
  });

  testWidgets('StartupChangelogWatcher displays dialog when update detected', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('cl_dialog_test_');
    final stateFile = File('${tempDir.path}/changelog_state.json');
    final firstRunFile = File('${tempDir.path}/app_first_run.json');
    firstRunFile.writeAsStringSync('{"introPlayed":true}');
    ChangelogStore.instance.setStorageFileForTesting(stateFile);
    ChangelogStore.instance.setFirstRunFileForTesting(firstRunFile);
    addTearDown(() {
      ChangelogStore.instance.setStorageFileForTesting(null);
      ChangelogStore.instance.setFirstRunFileForTesting(null);
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final mockService = ChangelogService(
      customLoader: () async => '''
## [1.4.1] (2026-11-20)

### Features

* **settings:** display model provider in dropdowns
''',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          changelogServiceProvider.overrideWithValue(mockService),
          hostEnvironmentServiceProvider.overrideWithValue(FakeHostEnvironmentService()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: Stack(children: [StartupChangelogWatcher(enableInTests: true), Text('App Root')])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('App Root'), findsOneWidget);
    expect(find.textContaining('1.4.1'), findsOneWidget);
    expect(find.text('display model provider in dropdowns'), findsOneWidget);

    // Tap close
    await tester.tap(find.byKey(const ValueKey('changelog-dialog-close-btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('changelog-dialog-close-btn')), findsNothing);
  });

  testWidgets('tapping a commit hash asks the link service to open its commit', (tester) async {
    final links = FakeLinkService();
    const release = ChangelogRelease(
      version: '1.5.0',
      date: '2026-11-20',
      features: [
        ChangelogItem(
          scope: 'chat',
          message: 'add read-only side conversations',
          commitHash: '2e48ed2',
          commitUrl: 'https://github.com/test/commit/2e48ed2',
          isFeature: true,
        ),
      ],
      fixes: [],
    );

    await tester.pumpWidget(
      buildTestDialog(release: release, overrides: [linkServiceProvider.overrideWithValue(links)]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2e48ed2'));
    await tester.pumpAndSettle();

    expect(links.opened, [Uri.parse('https://github.com/test/commit/2e48ed2')]);
  });

  testWidgets('StartupChangelogWatcher stays quiet on a test host unless enabled', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('cl_quiet_test_');
    ChangelogStore.instance.setStorageFileForTesting(File('${tempDir.path}/changelog_state.json'));
    ChangelogStore.instance.setFirstRunFileForTesting(
      File('${tempDir.path}/app_first_run.json')..writeAsStringSync('{"introPlayed":true}'),
    );
    addTearDown(() {
      ChangelogStore.instance.setStorageFileForTesting(null);
      ChangelogStore.instance.setFirstRunFileForTesting(null);
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final mockService = ChangelogService(
      customLoader: () async => '''
## [1.4.1] (2026-11-20)

### Features

* **settings:** display model provider in dropdowns
''',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          changelogServiceProvider.overrideWithValue(mockService),
          hostEnvironmentServiceProvider.overrideWithValue(
            FakeHostEnvironmentService(variables: const {'FLUTTER_TEST': 'true'}),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: Stack(children: [StartupChangelogWatcher(), Text('App Root')])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('App Root'), findsOneWidget);
    expect(find.byKey(const ValueKey('changelog-dialog-close-btn')), findsNothing);
  });
}

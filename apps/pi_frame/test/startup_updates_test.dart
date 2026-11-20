import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/update/startup_updates_provider.dart';
import 'package:pi_frame/features/updates/startup_update_banner.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MockStartupUpdateChecker implements StartupUpdateChecker {
  String? currentPi;
  String? latestPi;
  List<PackageUpdateInfo> packages;
  Object? packageError;
  Object? latestError;
  Future<List<PackageUpdateInfo>> Function()? onPackages;

  _MockStartupUpdateChecker({
    this.currentPi = '1.3.0',
    this.latestPi = '1.4.0',
    this.packages = const [
      PackageUpdateInfo(
        name: 'pi-caveman',
        currentVersion: '1.0.10',
        latestVersion: '1.0.11',
      ),
      PackageUpdateInfo(
        name: 'pi-web-access',
        currentVersion: '0.43.0',
        latestVersion: '0.44.0',
      ),
    ],
  });

  @override
  Future<String?> checkCurrentPiVersion() async => currentPi;

  @override
  Future<String?> checkLatestPiVersion() async {
    if (latestError != null) throw latestError!;
    return latestPi;
  }

  @override
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async {
    if (packageError != null) throw packageError!;
    return onPackages == null ? packages : await onPackages!();
  }
}

void main() {
  group('Package update availability', () {
    test('requires a strictly newer verified version', () {
      final package = <String, dynamic>{
        'source': 'npm:package',
        'version': '1.0.0',
        'latestVersion': '1.0.1',
      };
      expect(hasAvailablePiPackageUpdate(package), isTrue);
      expect(
        hasAvailablePiPackageUpdate({...package, 'latestVersion': '1.0.0'}),
        isFalse,
      );
      expect(
        hasAvailablePiPackageUpdate({...package, 'latestVersion': '0.9.0'}),
        isFalse,
      );
      expect(
        hasAvailablePiPackageUpdate({
          ...package,
          'version': '1.0.0+local',
          'latestVersion': '1.0.0+registry',
        }),
        isFalse,
      );
      expect(
        hasAvailablePiPackageUpdate({
          ...package,
          'version': '1.0.0-beta.2',
          'latestVersion': '1.0.0-beta.10',
        }),
        isTrue,
      );
    });

    test('pins, incompatibilities and unknown versions remain unavailable', () {
      final package = <String, dynamic>{
        'source': 'npm:package',
        'version': '1.0.0',
        'latestVersion': '2.0.0',
      };
      for (final fields in [
        {'pinnedVersion': '1.0.0'},
        {'updateError': 'Unsupported platform'},
        {'latestVersion': null},
        {'latestVersion': 'invalid'},
        {'version': null},
        {'source': ''},
      ]) {
        expect(hasAvailablePiPackageUpdate({...package, ...fields}), isFalse);
      }
    });
  });

  group('DefaultStartupUpdateChecker', () {
    test(
      'uses configured targets and excludes pinned, local and newer packages',
      () async {
        final checker = DefaultStartupUpdateChecker(
          listPackages: () async => [
            {
              'source': 'npm:package',
              'name': 'package',
              'version': '0.1.14',
              'latestVersion': '1.2.0',
            },
            {
              'source': 'npm:range-package@^1.0.0',
              'version': '1.9.0',
              'latestVersion': '1.9.0',
            },
            {
              'source': 'npm:pinned@1.0.0',
              'version': '1.0.0',
              'pinnedVersion': '1.0.0',
            },
            {'source': 'git:github.com/example/tools', 'version': '1.0.0'},
            {
              'source': 'npm:newer',
              'version': '2.0.0',
              'latestVersion': '1.9.0',
            },
            {
              'source': 'npm:next@next',
              'name': 'next',
              'version': '2.0.0-beta.2',
              'latestVersion': '2.0.0-beta.10',
            },
            {
              'source': 'npm:build',
              'version': '1.0.0+local',
              'latestVersion': '1.0.0+registry',
            },
            {
              'source': 'npm:unsupported',
              'version': '0.1.14',
              'latestVersion': '1.2.0',
              'updateError': 'Required dependency does not support Windows.',
            },
          ],
        );
        addTearDown(checker.dispose);
        expect(await checker.checkOutdatedPackages(), const [
          PackageUpdateInfo(
            name: 'package',
            currentVersion: '0.1.14',
            latestVersion: '1.2.0',
          ),
          PackageUpdateInfo(
            name: 'next',
            currentVersion: '2.0.0-beta.2',
            latestVersion: '2.0.0-beta.10',
          ),
        ]);
      },
    );

    test(
      'missing version verification is an error, not an empty update list',
      () async {
        final checker = DefaultStartupUpdateChecker(
          listPackages: () async => [
            {'source': 'npm:package', 'version': '1.0.0'},
          ],
        );
        addTearDown(checker.dispose);
        await expectLater(checker.checkOutdatedPackages(), throwsStateError);
      },
    );

    test('package command failures propagate', () async {
      final checker = DefaultStartupUpdateChecker(
        listPackages: () async => throw StateError('npm registry unavailable'),
      );
      addTearDown(checker.dispose);
      await expectLater(checker.checkOutdatedPackages(), throwsStateError);
    });

    test('registry failures and invalid responses propagate', () async {
      for (final response in [
        http.Response('unavailable', 503),
        http.Response('invalid JSON', 200),
        http.Response('{"version":"invalid"}', 200),
      ]) {
        final checker = DefaultStartupUpdateChecker(
          listPackages: () async => [],
          httpClient: MockClient((_) async => response),
        );
        addTearDown(checker.dispose);
        await expectLater(
          checker.checkLatestPiVersion(),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
        );
      }
    });
  });

  group('StartupUpdateState & Notifier', () {
    test('PackageUpdateInfo equality and json', () {
      const p1 = PackageUpdateInfo(
        name: 'pkg1',
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
      );
      const p2 = PackageUpdateInfo(
        name: 'pkg1',
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
      );
      expect(p1, equals(p2));
      expect(p1.toJson(), {
        'name': 'pkg1',
        'currentVersion': '1.0.0',
        'latestVersion': '2.0.0',
      });
    });

    test('StartupUpdateState shouldShowBanner logic', () {
      const stateEmpty = StartupUpdateState();
      expect(stateEmpty.hasAnyUpdate, isFalse);
      expect(stateEmpty.shouldShowBanner, isFalse);

      const stateCheckedWithPi = StartupUpdateState(
        hasChecked: true,
        piHasUpdate: true,
      );
      expect(stateCheckedWithPi.hasAnyUpdate, isTrue);
      expect(stateCheckedWithPi.shouldShowBanner, isTrue);

      final stateDismissed = stateCheckedWithPi.copyWith(isDismissed: true);
      expect(stateDismissed.shouldShowBanner, isFalse);
    });

    test('StartupUpdatesNotifier runs check and dismiss', () async {
      final mock = _MockStartupUpdateChecker();
      final container = ProviderContainer(
        overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(startupUpdatesProvider.notifier);
      expect(container.read(startupUpdatesProvider).hasChecked, isFalse);

      await notifier.checkUpdates();

      final state = container.read(startupUpdatesProvider);
      expect(state.hasChecked, isTrue);
      expect(state.piHasUpdate, isTrue);
      expect(state.currentPiVersion, '1.3.0');
      expect(state.latestPiVersion, '1.4.0');
      expect(state.outdatedPackages.length, 2);
      expect(state.shouldShowBanner, isTrue);

      notifier.dismiss();
      expect(container.read(startupUpdatesProvider).shouldShowBanner, isFalse);
    });

    test(
      'refresh removes installed updates and preserves Pi update state',
      () async {
        final mock = _MockStartupUpdateChecker();
        final container = ProviderContainer(
          overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(startupUpdatesProvider.notifier);
        await notifier.checkUpdates();
        mock.packages = [];
        await notifier.refreshPackages();
        final state = container.read(startupUpdatesProvider);
        expect(state.outdatedPackages, isEmpty);
        expect(state.piHasUpdate, isTrue);
        expect(state.currentPiVersion, '1.3.0');
      },
    );

    test(
      'failed rechecks keep known updates and expose the error until recovery',
      () async {
        final mock = _MockStartupUpdateChecker(currentPi: '1.4.0');
        final container = ProviderContainer(
          overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(startupUpdatesProvider.notifier);
        await notifier.checkUpdates();
        mock.packageError = StateError('Registry unavailable');
        await notifier.refreshPackages();
        expect(
          container.read(startupUpdatesProvider).outdatedPackages.length,
          2,
        );
        expect(
          container.read(startupUpdatesProvider).error,
          contains('Registry unavailable'),
        );
        mock.packageError = null;
        mock.packages = [];
        await notifier.refreshPackages();
        expect(container.read(startupUpdatesProvider).error, isNull);
        expect(
          container.read(startupUpdatesProvider).shouldShowBanner,
          isFalse,
        );
      },
    );

    test('a Pi registry failure does not suppress package updates', () async {
      final mock = _MockStartupUpdateChecker()
        ..latestError = StateError('Pi registry unavailable');
      final container = ProviderContainer(
        overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);
      await container.read(startupUpdatesProvider.notifier).checkUpdates();
      expect(container.read(startupUpdatesProvider).outdatedPackages.length, 2);
      expect(
        container.read(startupUpdatesProvider).error,
        contains('Pi registry unavailable'),
      );
    });

    test(
      'refresh waits for a startup check and replaces its stale result',
      () async {
        final pending = Completer<List<PackageUpdateInfo>>();
        var calls = 0;
        final mock = _MockStartupUpdateChecker(currentPi: '1.4.0')
          ..onPackages = () => ++calls == 1 ? pending.future : Future.value([]);
        final container = ProviderContainer(
          overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(startupUpdatesProvider.notifier);
        final checking = notifier.checkUpdates();
        final refreshing = notifier.refreshPackages();
        pending.complete(mock.packages);
        await Future.wait([checking, refreshing]);
        expect(calls, 2);
        expect(
          container.read(startupUpdatesProvider).outdatedPackages,
          isEmpty,
        );
        expect(
          container.read(startupUpdatesProvider).shouldShowBanner,
          isFalse,
        );
      },
    );

    test('a recheck can clear old nullable Pi versions', () async {
      final mock = _MockStartupUpdateChecker();
      final container = ProviderContainer(
        overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(startupUpdatesProvider.notifier);
      await notifier.checkUpdates();
      mock.currentPi = null;
      mock.latestPi = null;
      await notifier.checkUpdates();
      expect(container.read(startupUpdatesProvider).currentPiVersion, isNull);
      expect(container.read(startupUpdatesProvider).latestPiVersion, isNull);
      expect(container.read(startupUpdatesProvider).piHasUpdate, isFalse);
    });

    test('disposing during a check does not write disposed state', () async {
      final pending = Completer<List<PackageUpdateInfo>>();
      final mock = _MockStartupUpdateChecker()
        ..onPackages = () => pending.future;
      final container = ProviderContainer(
        overrides: [startupUpdateCheckerProvider.overrideWithValue(mock)],
      );
      final checking = container
          .read(startupUpdatesProvider.notifier)
          .refreshPackages();
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      pending.complete([]);
      await checking;
    });
  });

  testWidgets('StartupUpdateBanner renders details and handles actions', (
    tester,
  ) async {
    final mock = _MockStartupUpdateChecker();
    final langNotifier = AppLanguageNotifier()..setLanguage(AppLanguage.it);
    final container = ProviderContainer(
      overrides: [
        startupUpdateCheckerProvider.overrideWithValue(mock),
        appLanguageProvider.overrideWith((ref) => langNotifier),
      ],
    );
    addTearDown(container.dispose);

    // Run check first so updates are available
    await container.read(startupUpdatesProvider.notifier).checkUpdates();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: const Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Main Content')),
                StartupUpdateBanner(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify banner is shown
    expect(find.text('Aggiornamenti rilevati'), findsOneWidget);
    expect(find.textContaining('Pi CLI: 1.3.0 → 1.4.0'), findsOneWidget);
    expect(find.textContaining('pi-caveman, pi-web-access'), findsOneWidget);

    // Verify Open Details / Update button opens settings tab 0 (Pi CLI)
    final openBtn = find.byKey(const ValueKey('startup-update-open-btn'));
    expect(openBtn, findsOneWidget);
    await tester.tap(openBtn);
    await tester.pumpAndSettle();

    expect(container.read(showSettingsProvider), isTrue);
    expect(container.read(settingsTabIndexProvider), 0);
    // And banner is now dismissed
    expect(find.byKey(const ValueKey('startup-update-open-btn')), findsNothing);
  });

  testWidgets('StartupUpdateBanner can be dismissed with close button', (
    tester,
  ) async {
    final mock = _MockStartupUpdateChecker(
      currentPi: '1.4.0',
      latestPi: '1.4.0', // No Pi update
      packages: const [
        PackageUpdateInfo(
          name: 'pi-caveman',
          currentVersion: '1.0.10',
          latestVersion: '1.0.11',
        ),
      ],
    );
    final langNotifier = AppLanguageNotifier()..setLanguage(AppLanguage.it);
    final container = ProviderContainer(
      overrides: [
        startupUpdateCheckerProvider.overrideWithValue(mock),
        appLanguageProvider.overrideWith((ref) => langNotifier),
      ],
    );
    addTearDown(container.dispose);

    await container.read(startupUpdatesProvider.notifier).checkUpdates();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: const Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Main Content')),
                StartupUpdateBanner(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aggiornamenti rilevati'), findsOneWidget);
    expect(find.textContaining('pi-caveman'), findsOneWidget);

    // Tap dismiss
    final dismissBtn = find.byKey(const ValueKey('startup-update-dismiss-btn'));
    expect(dismissBtn, findsOneWidget);
    await tester.tap(dismissBtn);
    await tester.pumpAndSettle();

    // Banner is dismissed
    expect(find.text('Aggiornamenti rilevati'), findsNothing);
    expect(container.read(startupUpdatesProvider).isDismissed, isTrue);
  });
}

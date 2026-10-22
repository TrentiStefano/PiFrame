import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/update/startup_updates_provider.dart';
import 'package:pi_frame/features/updates/startup_update_banner.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _MockStartupUpdateChecker implements StartupUpdateChecker {
  final String? currentPi;
  final String? latestPi;
  final List<PackageUpdateInfo> packages;

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
  Future<String?> checkLatestPiVersion() async => latestPi;

  @override
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async => packages;
}

void main() {
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
    expect(find.text('Aggiornamenti Rilevati'), findsOneWidget);
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

    expect(find.text('Aggiornamenti Rilevati'), findsOneWidget);
    expect(find.textContaining('pi-caveman'), findsOneWidget);

    // Tap dismiss
    final dismissBtn = find.byKey(const ValueKey('startup-update-dismiss-btn'));
    expect(dismissBtn, findsOneWidget);
    await tester.tap(dismissBtn);
    await tester.pumpAndSettle();

    // Banner is dismissed
    expect(find.text('Aggiornamenti Rilevati'), findsNothing);
    expect(container.read(startupUpdatesProvider).isDismissed, isTrue);
  });
}

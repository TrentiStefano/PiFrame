import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/update/github_update_client.dart';
import 'package:pi_frame/data/update/installer_launcher.dart';
import 'package:pi_frame/data/update/update_providers.dart';
import 'package:pi_frame/data/update/update_storage.dart';
import 'package:pi_frame/domain/update/update_models.dart';

class MockUpdateClient implements UpdateClient {
  AppRelease? nextRelease;
  Exception? errorToThrow;

  @override
  Future<AppRelease?> fetchLatestRelease() async {
    if (errorToThrow != null) throw errorToThrow!;
    return nextRelease;
  }

  @override
  Stream<DownloadProgress> downloadAsset({
    required ReleaseAsset asset,
    required String destinationPath,
    Future<void>? cancelSignal,
  }) async* {
    yield const DownloadProgress(downloadedBytes: 50, totalBytes: 100, fraction: 0.5);
    yield const DownloadProgress(downloadedBytes: 100, totalBytes: 100, fraction: 1.0);
  }
}

class MockInstallerLauncher implements InstallerLauncher {
  String? launchedFilePath;
  AppRelease? launchedRelease;
  String? openedUrl;

  @override
  Future<void> launchInstaller(String filePath, {required AppRelease release}) async {
    launchedFilePath = filePath;
    launchedRelease = release;
  }

  @override
  Future<void> openReleasePage(String url) async {
    openedUrl = url;
  }
}

void main() {
  group('UpdateController', () {
    late MemoryUpdateStorage storage;
    late MockUpdateClient client;
    late MockInstallerLauncher launcher;
    late ProviderContainer container;

    setUp(() {
      storage = MemoryUpdateStorage();
      client = MockUpdateClient();
      launcher = MockInstallerLauncher();

      container = ProviderContainer(
        overrides: [
          updateStorageProvider.overrideWithValue(storage),
          updateClientProvider.overrideWithValue(client),
          installerLauncherProvider.overrideWithValue(launcher),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('sets updateAvailable when GitHub has newer version', () async {
      client.nextRelease = AppRelease(
        tagName: 'v1.4.0',
        name: 'PiFrame v1.4.0',
        body: 'Awesome update',
        htmlUrl: 'https://github.com/TrentiStefano/piframe/releases/tag/v1.4.0',
        assets: [
          const ReleaseAsset(
            name: 'PiFrame-Setup-1.4.0-windows-x64.exe',
            downloadUrl: 'https://github.com/TrentiStefano/piframe/releases/download/v1.4.0/PiFrame-Setup-1.4.0-windows-x64.exe',
            size: 100000,
            contentType: 'application/octet-stream',
          ),
        ],
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkForUpdates();

      final state = container.read(updateControllerProvider);
      expect(state.status, UpdateStatus.updateAvailable);
      expect(state.latestRelease?.tagName, 'v1.4.0');
      expect(state.selectedAsset?.name, 'PiFrame-Setup-1.4.0-windows-x64.exe');
      expect(container.read(hasUpdateBadgeProvider), isTrue);

      final settings = container.read(updateSettingsProvider);
      expect(settings.lastChecked, isNotNull);
    });

    test('sets upToDate when GitHub has same or older version', () async {
      client.nextRelease = AppRelease(
        tagName: 'v1.3.0',
        name: 'PiFrame v1.3.0',
        body: 'Current release',
        htmlUrl: 'https://github.com/TrentiStefano/piframe/releases/tag/v1.3.0',
        assets: const [],
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkForUpdates();

      final state = container.read(updateControllerProvider);
      expect(state.status, UpdateStatus.upToDate);
      expect(container.read(hasUpdateBadgeProvider), isFalse);
    });

    test('sets error status when network fails', () async {
      client.errorToThrow = const UpdateException('Rete non disponibile');

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkForUpdates();

      final state = container.read(updateControllerProvider);
      expect(state.status, UpdateStatus.error);
      expect(state.errorMessage, contains('Rete non disponibile'));
    });

    test('downloads update and handles installation launch', () async {
      final release = AppRelease(
        tagName: 'v1.4.0',
        name: 'v1.4.0',
        body: 'Changelog',
        htmlUrl: 'https://github.com/test',
        assets: [
          const ReleaseAsset(
            name: 'setup.exe',
            downloadUrl: 'https://github.com/download/setup.exe',
            size: 100,
            contentType: 'application/octet-stream',
          ),
        ],
      );
      client.nextRelease = release;

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkForUpdates();

      await controller.downloadUpdate();
      final downloadedState = container.read(updateControllerProvider);
      expect(downloadedState.status, UpdateStatus.readyToInstall);
      expect(downloadedState.downloadProgress, 1.0);
      expect(downloadedState.downloadedFilePath, isNotNull);

      await controller.installUpdate();
      expect(launcher.launchedFilePath, downloadedState.downloadedFilePath);
      expect(launcher.launchedRelease?.tagName, 'v1.4.0');
    });

    test('update settings can toggle auto-check and change interval', () async {
      final settingsNotifier = container.read(updateSettingsProvider.notifier);

      expect(container.read(updateSettingsProvider).autoCheckEnabled, isFalse);

      await settingsNotifier.setAutoCheckEnabled(true);
      expect(container.read(updateSettingsProvider).autoCheckEnabled, isTrue);

      await settingsNotifier.setInterval(UpdateCheckInterval.daily);
      expect(container.read(updateSettingsProvider).interval, UpdateCheckInterval.daily);

      final saved = await storage.loadSettings();
      expect(saved.autoCheckEnabled, isTrue);
      expect(saved.interval, UpdateCheckInterval.daily);
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../runtime/app_version.dart';
import '../../domain/update/semver.dart';
import '../../domain/update/update_models.dart';
import '../language/language_settings.dart';
import '../language/strings_settings.dart';
import 'github_update_client.dart';
import 'release_platform.dart';
import 'installer_launcher.dart';
import 'update_storage.dart';

final updateStorageProvider = Provider<UpdateStorage>((ref) {
  return FileUpdateStorage();
});

final updateClientProvider = Provider<UpdateClient>((ref) {
  return GithubUpdateClient();
});

final installerLauncherProvider = Provider<InstallerLauncher>((ref) {
  return const PlatformInstallerLauncher();
});

class UpdateSettingsNotifier extends StateNotifier<UpdateSettings> {
  final UpdateStorage _storage;
  bool _userModified = false;

  UpdateSettingsNotifier(this._storage) : super(const UpdateSettings()) {
    unawaited(_load());
  }

  Future<void> _load() async {
    final loaded = await _storage.loadSettings();
    if (!_userModified) {
      state = loaded;
    }
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    _userModified = true;
    state = state.copyWith(autoCheckEnabled: enabled);
    await _storage.saveSettings(state);
  }

  Future<void> setInterval(UpdateCheckInterval interval) async {
    _userModified = true;
    state = state.copyWith(interval: interval);
    await _storage.saveSettings(state);
  }

  Future<void> recordCheckCompleted(DateTime timestamp) async {
    _userModified = true;
    state = state.copyWith(lastChecked: timestamp);
    await _storage.saveSettings(state);
  }
}

final updateSettingsProvider = StateNotifierProvider<UpdateSettingsNotifier, UpdateSettings>((ref) {
  final storage = ref.watch(updateStorageProvider);
  return UpdateSettingsNotifier(storage);
});

class UpdateController extends StateNotifier<UpdateState> {
  final Ref _ref;
  final String currentVersionString;
  Completer<void>? _cancelCompleter;

  UpdateController(this._ref, {this.currentVersionString = piFrameVersion})
    : super(UpdateState(currentVersion: currentVersionString));

  UpdateClient get _client => _ref.read(updateClientProvider);
  InstallerLauncher get _launcher => _ref.read(installerLauncherProvider);
  AppStrings get _strings => _ref.read(appStringsProvider);

  /// The translated reason for an update failure, or the raw text for other errors.
  String _errorText(Object e) {
    if (e is UpdateException && e.failure != null) return _strings.updateFailureMessage(e.failure!, e.statusCode);
    return e.toString();
  }

  Future<void> checkForUpdates({bool isManual = true}) async {
    if (state.isChecking || state.isDownloading) return;

    state = state.copyWith(status: UpdateStatus.checking, clearErrorMessage: true);

    try {
      final release = await _client.fetchLatestRelease();
      final now = DateTime.now();
      await _ref.read(updateSettingsProvider.notifier).recordCheckCompleted(now);

      if (release == null) {
        state = state.copyWith(status: UpdateStatus.upToDate);
        return;
      }

      final currentSemVer = SemVer.tryParse(currentVersionString);
      final releaseSemVer = release.semVer;

      if (releaseSemVer != null && currentSemVer != null && releaseSemVer > currentSemVer) {
        final asset = release.findPlatformAsset(platform: currentReleasePlatform(), arch: currentReleaseArch());
        state = state.copyWith(status: UpdateStatus.updateAvailable, latestRelease: release, selectedAsset: asset);
      } else {
        state = state.copyWith(status: UpdateStatus.upToDate, latestRelease: release);
      }
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, errorMessage: _errorText(e));
    }
  }

  Future<void> downloadUpdate({ReleaseAsset? assetOverride}) async {
    final release = state.latestRelease;
    final asset =
        assetOverride ??
        state.selectedAsset ??
        release?.findPlatformAsset(platform: currentReleasePlatform(), arch: currentReleaseArch());

    if (release == null || asset == null) {
      state = state.copyWith(status: UpdateStatus.error, errorMessage: _strings.updateNoAssetForPlatform);
      return;
    }

    state = state.copyWith(
      status: UpdateStatus.downloading,
      selectedAsset: asset,
      downloadProgress: 0.0,
      downloadedBytes: 0,
      totalBytes: asset.size,
      clearErrorMessage: true,
    );

    final safeFilename = GithubUpdateClient.sanitizeFilename(asset.name);
    final tempDir = Directory.systemTemp.path;
    final destPath = p.join(tempDir, 'pi-frame-updates', safeFilename);

    _cancelCompleter = Completer<void>();

    try {
      final progressStream = _client.downloadAsset(
        asset: asset,
        destinationPath: destPath,
        cancelSignal: _cancelCompleter?.future,
      );

      await for (final progress in progressStream) {
        state = state.copyWith(
          downloadProgress: progress.fraction,
          downloadedBytes: progress.downloadedBytes,
          totalBytes: progress.totalBytes,
        );
      }

      state = state.copyWith(status: UpdateStatus.readyToInstall, downloadProgress: 1.0, downloadedFilePath: destPath);
    } catch (e) {
      if (_cancelCompleter != null && _cancelCompleter!.isCompleted) {
        state = state.copyWith(status: UpdateStatus.updateAvailable, downloadProgress: 0.0);
      } else {
        state = state.copyWith(status: UpdateStatus.error, errorMessage: _strings.updateDownloadFailed(_errorText(e)));
      }
    } finally {
      _cancelCompleter = null;
    }
  }

  void cancelDownload() {
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
    state = state.copyWith(status: UpdateStatus.updateAvailable, downloadProgress: 0.0);
  }

  Future<void> installUpdate() async {
    final path = state.downloadedFilePath;
    final release = state.latestRelease;
    if (path == null || release == null) return;

    state = state.copyWith(status: UpdateStatus.installing);

    try {
      await _launcher.launchInstaller(path, release: release);
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, errorMessage: _strings.updateInstallLaunchFailed('$e'));
    }
  }

  Future<void> openReleasePage() async {
    final release = state.latestRelease;
    final url = release?.htmlUrl ?? 'https://github.com/${GithubUpdateClient.defaultRepository}/releases';
    await _launcher.openReleasePage(url);
  }

  void reset() {
    state = UpdateState(currentVersion: currentVersionString);
  }
}

final updateControllerProvider = StateNotifierProvider<UpdateController, UpdateState>((ref) {
  return UpdateController(ref);
});

final hasUpdateBadgeProvider = Provider<bool>((ref) {
  final updateState = ref.watch(updateControllerProvider);
  return updateState.hasUpdate;
});

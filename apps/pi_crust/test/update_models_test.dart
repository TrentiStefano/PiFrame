import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/domain/update/update_models.dart';

void main() {
  group('ReleaseAsset', () {
    test('parses from JSON correctly', () {
      final asset = ReleaseAsset.fromJson({
        'name': 'Pi-Crust-Setup-1.4.0-windows-x64.exe',
        'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-Setup-1.4.0-windows-x64.exe',
        'size': 85000000,
        'content_type': 'application/octet-stream',
      });

      expect(asset.name, 'Pi-Crust-Setup-1.4.0-windows-x64.exe');
      expect(asset.downloadUrl, contains('windows-x64.exe'));
      expect(asset.size, 85000000);
      expect(asset.isWindowsInstaller, isTrue);
      expect(asset.isMacDmg, isFalse);
      expect(asset.isLinuxDeb, isFalse);
    });

    test('detects macOS and Linux assets', () {
      final macArm = ReleaseAsset.fromJson({
        'name': 'Pi-Crust-1.4.0-macos-arm64.dmg',
        'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-1.4.0-macos-arm64.dmg',
        'size': 70000000,
      });
      expect(macArm.isMacDmg, isTrue);
      expect(macArm.isMacArm, isTrue);
      expect(macArm.isMacIntel, isFalse);

      final macIntel = ReleaseAsset.fromJson({
        'name': 'Pi-Crust-1.4.0-macos-x64.dmg',
        'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-1.4.0-macos-x64.dmg',
        'size': 72000000,
      });
      expect(macIntel.isMacDmg, isTrue);
      expect(macIntel.isMacIntel, isTrue);
      expect(macIntel.isMacArm, isFalse);

      final linuxDeb = ReleaseAsset.fromJson({
        'name': 'Pi-Crust-1.4.0-linux-amd64.deb',
        'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-1.4.0-linux-amd64.deb',
        'size': 65000000,
      });
      expect(linuxDeb.isLinuxDeb, isTrue);
      expect(linuxDeb.isWindowsInstaller, isFalse);
    });
  });

  group('AppRelease', () {
    test('finds correct platform asset', () {
      final release = AppRelease.fromJson({
        'tag_name': 'v1.4.0',
        'name': 'v1.4.0 Release',
        'body': 'Changelog: new features',
        'html_url': 'https://github.com/TrentiStefano/pi-crust/releases/tag/v1.4.0',
        'assets': [
          {
            'name': 'Pi-Crust-Setup-1.4.0-windows-x64.exe',
            'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-Setup-1.4.0-windows-x64.exe',
            'size': 85000000,
          },
          {
            'name': 'Pi-Crust-1.4.0-macos-arm64.dmg',
            'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-1.4.0-macos-arm64.dmg',
            'size': 70000000,
          },
          {
            'name': 'Pi-Crust-1.4.0-macos-x64.dmg',
            'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-1.4.0-macos-x64.dmg',
            'size': 72000000,
          },
          {
            'name': 'Pi-Crust-1.4.0-linux-amd64.deb',
            'browser_download_url': 'https://github.com/TrentiStefano/pi-crust/releases/download/v1.4.0/Pi-Crust-1.4.0-linux-amd64.deb',
            'size': 65000000,
          },
        ],
      });

      expect(release.semVer?.major, 1);
      expect(release.semVer?.minor, 4);

      final winAsset = release.findPlatformAsset(
        platformOverride: TargetPlatform.windows,
      );
      expect(winAsset?.name, 'Pi-Crust-Setup-1.4.0-windows-x64.exe');

      final macArmAsset = release.findPlatformAsset(
        platformOverride: TargetPlatform.macOS,
        archOverride: 'arm64',
      );
      expect(macArmAsset?.name, 'Pi-Crust-1.4.0-macos-arm64.dmg');

      final macIntelAsset = release.findPlatformAsset(
        platformOverride: TargetPlatform.macOS,
        archOverride: 'x64',
      );
      expect(macIntelAsset?.name, 'Pi-Crust-1.4.0-macos-x64.dmg');

      final linuxAsset = release.findPlatformAsset(
        platformOverride: TargetPlatform.linux,
      );
      expect(linuxAsset?.name, 'Pi-Crust-1.4.0-linux-amd64.deb');
    });
  });

  group('UpdateCheckInterval & UpdateSettings', () {
    test('intervals have correct durations and labels', () {
      expect(UpdateCheckInterval.daily.duration, const Duration(days: 1));
      expect(UpdateCheckInterval.weekly.duration, const Duration(days: 7));
      expect(UpdateCheckInterval.monthly.duration, const Duration(days: 30));

      expect(UpdateCheckInterval.fromId('daily'), UpdateCheckInterval.daily);
      expect(UpdateCheckInterval.fromId('weekly'), UpdateCheckInterval.weekly);
      expect(UpdateCheckInterval.fromId('monthly'), UpdateCheckInterval.monthly);
      expect(UpdateCheckInterval.fromId('other'), UpdateCheckInterval.weekly);
    });

    test('default settings are opt-in (autoCheckEnabled = false)', () {
      const defaultSettings = UpdateSettings();
      expect(defaultSettings.autoCheckEnabled, isFalse);
      expect(defaultSettings.interval, UpdateCheckInterval.weekly);
      expect(defaultSettings.lastChecked, isNull);

      final now = DateTime.now();
      expect(defaultSettings.shouldCheckNow(now), isFalse);
    });

    test('shouldCheckNow logic when enabled', () {
      final now = DateTime(2026, 10, 14, 12, 0);

      // When enabled and never checked, should check
      const enabledNeverChecked = UpdateSettings(
        autoCheckEnabled: true,
        interval: UpdateCheckInterval.daily,
      );
      expect(enabledNeverChecked.shouldCheckNow(now), isTrue);

      // When enabled and checked 2 hours ago for daily interval -> should NOT check
      final checkedRecently = UpdateSettings(
        autoCheckEnabled: true,
        interval: UpdateCheckInterval.daily,
        lastChecked: now.subtract(const Duration(hours: 2)),
      );
      expect(checkedRecently.shouldCheckNow(now), isFalse);

      // When enabled and checked 25 hours ago for daily interval -> SHOULD check
      final checkedYesterday = UpdateSettings(
        autoCheckEnabled: true,
        interval: UpdateCheckInterval.daily,
        lastChecked: now.subtract(const Duration(hours: 25)),
      );
      expect(checkedYesterday.shouldCheckNow(now), isTrue);

      // For weekly interval
      final checkedSixDaysAgo = UpdateSettings(
        autoCheckEnabled: true,
        interval: UpdateCheckInterval.weekly,
        lastChecked: now.subtract(const Duration(days: 6)),
      );
      expect(checkedSixDaysAgo.shouldCheckNow(now), isFalse);

      final checkedEightDaysAgo = UpdateSettings(
        autoCheckEnabled: true,
        interval: UpdateCheckInterval.weekly,
        lastChecked: now.subtract(const Duration(days: 8)),
      );
      expect(checkedEightDaysAgo.shouldCheckNow(now), isTrue);
    });

    test('serializes and deserializes to/from JSON accurately', () {
      final original = UpdateSettings(
        autoCheckEnabled: true,
        interval: UpdateCheckInterval.monthly,
        lastChecked: DateTime(2026, 10, 14, 10, 30),
      );

      final json = original.toJson();
      expect(json['autoCheckEnabled'], isTrue);
      expect(json['interval'], 'monthly');
      expect(json['lastChecked'], isNotNull);

      final reconstructed = UpdateSettings.fromJson(json);
      expect(reconstructed.autoCheckEnabled, original.autoCheckEnabled);
      expect(reconstructed.interval, original.interval);
      expect(reconstructed.lastChecked, original.lastChecked);
    });
  });
}

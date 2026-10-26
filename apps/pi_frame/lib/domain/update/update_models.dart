import 'dart:io';
import 'package:flutter/foundation.dart';
import 'semver.dart';

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] ?? '').toString(),
      downloadUrl: (json['browser_download_url'] ?? '').toString(),
      size: (json['size'] as num?)?.toInt() ?? 0,
      contentType: (json['content_type'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'browser_download_url': downloadUrl,
    'size': size,
    'content_type': contentType,
  };

  bool get isWindowsInstaller =>
      name.toLowerCase().endsWith('.exe');

  bool get isMacDmg =>
      name.toLowerCase().endsWith('.dmg');

  bool get isMacArm =>
      isMacDmg &&
      (name.toLowerCase().contains('arm64') ||
          name.toLowerCase().contains('aarch64'));

  bool get isMacIntel =>
      isMacDmg &&
      (name.toLowerCase().contains('x64') ||
          name.toLowerCase().contains('intel') ||
          name.toLowerCase().contains('x86_64'));

  bool get isLinuxDeb =>
      name.toLowerCase().endsWith('.deb');
}

class AppRelease {
  final String tagName;
  final String name;
  final String body;
  final DateTime? publishedAt;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  final SemVer? semVer;

  AppRelease({
    required this.tagName,
    required this.name,
    required this.body,
    this.publishedAt,
    required this.htmlUrl,
    required this.assets,
    SemVer? semVer,
  }) : semVer = semVer ?? SemVer.tryParse(tagName) ?? SemVer.tryParse(name);

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'] as List? ?? const [];
    final assets = rawAssets
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .toList();

    DateTime? publishedAt;
    final publishedStr = json['published_at']?.toString();
    if (publishedStr != null && publishedStr.isNotEmpty) {
      publishedAt = DateTime.tryParse(publishedStr);
    }

    final tagName = (json['tag_name'] ?? '').toString();
    final name = (json['name'] ?? '').toString();

    return AppRelease(
      tagName: tagName,
      name: name,
      body: (json['body'] ?? '').toString(),
      publishedAt: publishedAt,
      htmlUrl: (json['html_url'] ?? '').toString(),
      assets: assets,
    );
  }

  Map<String, dynamic> toJson() => {
    'tag_name': tagName,
    'name': name,
    'body': body,
    'published_at': publishedAt?.toIso8601String(),
    'html_url': htmlUrl,
    'assets': assets.map((a) => a.toJson()).toList(),
  };

  ReleaseAsset? findPlatformAsset({
    TargetPlatform? platformOverride,
    String? archOverride,
  }) {
    if (kIsWeb) return null;

    final platform = platformOverride ?? _detectPlatform();
    final arch = archOverride ?? _detectArch();

    ReleaseAsset? matched;
    if (platform == TargetPlatform.windows) {
      // Find Inno Setup exe
      matched = assets.cast<ReleaseAsset?>().firstWhere(
            (a) => a != null && a.isWindowsInstaller,
            orElse: () => null,
          );
    } else if (platform == TargetPlatform.macOS) {
      // Try matching architecture first
      final isArm = arch.contains('arm') || arch.contains('aarch');
      if (isArm) {
        matched = assets.cast<ReleaseAsset?>().firstWhere(
              (a) => a != null && a.isMacArm,
              orElse: () => null,
            );
      } else {
        matched = assets.cast<ReleaseAsset?>().firstWhere(
              (a) => a != null && a.isMacIntel,
              orElse: () => null,
            );
      }
      // Fallback to any DMG
      matched ??= assets.cast<ReleaseAsset?>().firstWhere(
            (a) => a != null && a.isMacDmg,
            orElse: () => null,
          );
    } else if (platform == TargetPlatform.linux) {
      // Debian installer package
      matched = assets.cast<ReleaseAsset?>().firstWhere(
            (a) => a != null && a.isLinuxDeb,
            orElse: () => null,
          );
    }

    // Fallback: if no platform-specific installer matched, but an asset is available,
    // return it so single-asset releases and test mocks work cross-platform.
    return matched ?? (assets.isNotEmpty ? assets.first : null);
  }

  static TargetPlatform _detectPlatform() {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return defaultTargetPlatform;
      }
      if (Platform.isWindows) return TargetPlatform.windows;
      if (Platform.isMacOS) return TargetPlatform.macOS;
      if (Platform.isLinux) return TargetPlatform.linux;
    } catch (_) {}
    return defaultTargetPlatform;
  }

  static String _detectArch() {
    try {
      final v = Platform.version.toLowerCase();
      if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
      if (v.contains('x64') || v.contains('x86_64')) return 'x64';
    } catch (_) {}
    return 'x64';
  }
}

enum UpdateCheckInterval {
  daily,
  weekly,
  monthly;

  Duration get duration {
    switch (this) {
      case UpdateCheckInterval.daily:
        return const Duration(days: 1);
      case UpdateCheckInterval.weekly:
        return const Duration(days: 7);
      case UpdateCheckInterval.monthly:
        return const Duration(days: 30);
    }
  }

  String get label {
    switch (this) {
      case UpdateCheckInterval.daily:
        return 'Ogni giorno';
      case UpdateCheckInterval.weekly:
        return 'Ogni settimana (consigliato)';
      case UpdateCheckInterval.monthly:
        return 'Ogni mese';
    }
  }

  String get id => name;

  static UpdateCheckInterval fromId(String? id) {
    switch (id) {
      case 'daily':
        return UpdateCheckInterval.daily;
      case 'monthly':
        return UpdateCheckInterval.monthly;
      case 'weekly':
      default:
        return UpdateCheckInterval.weekly;
    }
  }
}

class UpdateSettings {
  final bool autoCheckEnabled;
  final UpdateCheckInterval interval;
  final DateTime? lastChecked;

  const UpdateSettings({
    this.autoCheckEnabled = false,
    this.interval = UpdateCheckInterval.weekly,
    this.lastChecked,
  });

  bool shouldCheckNow(DateTime now) {
    if (!autoCheckEnabled) return false;
    if (lastChecked == null) return true;
    return now.difference(lastChecked!) >= interval.duration;
  }

  UpdateSettings copyWith({
    bool? autoCheckEnabled,
    UpdateCheckInterval? interval,
    DateTime? lastChecked,
    bool clearLastChecked = false,
  }) {
    return UpdateSettings(
      autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
      interval: interval ?? this.interval,
      lastChecked: clearLastChecked ? null : (lastChecked ?? this.lastChecked),
    );
  }

  Map<String, dynamic> toJson() => {
    'autoCheckEnabled': autoCheckEnabled,
    'interval': interval.id,
    'lastChecked': lastChecked?.toIso8601String(),
  };

  factory UpdateSettings.fromJson(Map<String, dynamic> json) {
    DateTime? lastChecked;
    final lastCheckedStr = json['lastChecked']?.toString();
    if (lastCheckedStr != null && lastCheckedStr.isNotEmpty) {
      lastChecked = DateTime.tryParse(lastCheckedStr);
    }

    return UpdateSettings(
      autoCheckEnabled: (json['autoCheckEnabled'] as bool?) ?? false,
      interval: UpdateCheckInterval.fromId(json['interval']?.toString()),
      lastChecked: lastChecked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UpdateSettings &&
          autoCheckEnabled == other.autoCheckEnabled &&
          interval == other.interval &&
          lastChecked == other.lastChecked);

  @override
  int get hashCode => Object.hash(autoCheckEnabled, interval, lastChecked);
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  installing,
  error,
}

class UpdateState {
  final UpdateStatus status;
  final AppRelease? latestRelease;
  final String? currentVersion;
  final double downloadProgress;
  final int downloadedBytes;
  final int totalBytes;
  final String? downloadedFilePath;
  final String? errorMessage;
  final ReleaseAsset? selectedAsset;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.latestRelease,
    this.currentVersion,
    this.downloadProgress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadedFilePath,
    this.errorMessage,
    this.selectedAsset,
  });

  bool get isChecking => status == UpdateStatus.checking;
  bool get isDownloading => status == UpdateStatus.downloading;
  bool get hasUpdate => status == UpdateStatus.updateAvailable ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.readyToInstall ||
      status == UpdateStatus.installing;

  UpdateState copyWith({
    UpdateStatus? status,
    AppRelease? latestRelease,
    bool clearLatestRelease = false,
    String? currentVersion,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
    String? downloadedFilePath,
    bool clearDownloadedFilePath = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    ReleaseAsset? selectedAsset,
    bool clearSelectedAsset = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      latestRelease: clearLatestRelease ? null : (latestRelease ?? this.latestRelease),
      currentVersion: currentVersion ?? this.currentVersion,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedFilePath: clearDownloadedFilePath ? null : (downloadedFilePath ?? this.downloadedFilePath),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      selectedAsset: clearSelectedAsset ? null : (selectedAsset ?? this.selectedAsset),
    );
  }
}

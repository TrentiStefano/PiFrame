import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/update/semver.dart';

class PackageUpdateInfo {
  final String name;
  final String currentVersion;
  final String latestVersion;

  const PackageUpdateInfo({
    required this.name,
    required this.currentVersion,
    required this.latestVersion,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'currentVersion': currentVersion,
    'latestVersion': latestVersion,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackageUpdateInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          currentVersion == other.currentVersion &&
          latestVersion == other.latestVersion;

  @override
  int get hashCode =>
      name.hashCode ^ currentVersion.hashCode ^ latestVersion.hashCode;
}

class StartupUpdateState {
  final bool isChecking;
  final bool hasChecked;
  final bool piHasUpdate;
  final String? currentPiVersion;
  final String? latestPiVersion;
  final List<PackageUpdateInfo> outdatedPackages;
  final bool isDismissed;
  final String? error;

  const StartupUpdateState({
    this.isChecking = false,
    this.hasChecked = false,
    this.piHasUpdate = false,
    this.currentPiVersion,
    this.latestPiVersion,
    this.outdatedPackages = const [],
    this.isDismissed = false,
    this.error,
  });

  bool get hasAnyUpdate => piHasUpdate || outdatedPackages.isNotEmpty;
  bool get shouldShowBanner => hasChecked && hasAnyUpdate && !isDismissed;

  StartupUpdateState copyWith({
    bool? isChecking,
    bool? hasChecked,
    bool? piHasUpdate,
    String? currentPiVersion,
    String? latestPiVersion,
    List<PackageUpdateInfo>? outdatedPackages,
    bool? isDismissed,
    String? error,
  }) {
    return StartupUpdateState(
      isChecking: isChecking ?? this.isChecking,
      hasChecked: hasChecked ?? this.hasChecked,
      piHasUpdate: piHasUpdate ?? this.piHasUpdate,
      currentPiVersion: currentPiVersion ?? this.currentPiVersion,
      latestPiVersion: latestPiVersion ?? this.latestPiVersion,
      outdatedPackages: outdatedPackages ?? this.outdatedPackages,
      isDismissed: isDismissed ?? this.isDismissed,
      error: error,
    );
  }
}

abstract class StartupUpdateChecker {
  Future<String?> checkCurrentPiVersion();
  Future<String?> checkLatestPiVersion();
  Future<List<PackageUpdateInfo>> checkOutdatedPackages();
}

class DefaultStartupUpdateChecker implements StartupUpdateChecker {
  final http.Client _httpClient;

  DefaultStartupUpdateChecker({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  Future<String?> checkCurrentPiVersion() async {
    if (kIsWeb) return null;
    try {
      final result = await Process.run(
        'pi',
        ['--version'],
        runInShell: true,
      ).timeout(const Duration(seconds: 4));
      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<String?> checkLatestPiVersion() async {
    try {
      final res = await _httpClient.get(
        Uri.parse(
          'https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent/latest',
        ),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['version']?.toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async {
    if (kIsWeb) return const [];
    try {
      final env = Platform.environment;
      final home = Platform.isWindows
          ? (env['USERPROFILE'] ?? 'C:\\Users\\Default')
          : (env['HOME'] ?? '/tmp');
      final npmDir = Directory('$home/.pi/agent/npm');
      if (!npmDir.existsSync()) {
        return const [];
      }

      // npm outdated exits with 1 when outdated packages are found.
      final result = await Process.run(
        'npm',
        ['outdated', '--json'],
        runInShell: true,
        workingDirectory: npmDir.path,
      ).timeout(const Duration(seconds: 8));

      final stdout = result.stdout.toString().trim();
      if (stdout.isEmpty || !stdout.startsWith('{')) {
        return const [];
      }

      final json = jsonDecode(stdout) as Map<String, dynamic>;
      final list = <PackageUpdateInfo>[];
      for (final entry in json.entries) {
        if (entry.value is Map<String, dynamic>) {
          final pkgMap = entry.value as Map<String, dynamic>;
          final current = pkgMap['current']?.toString() ?? '';
          final latest = pkgMap['latest']?.toString() ?? '';
          if (current.isNotEmpty && latest.isNotEmpty && current != latest) {
            list.add(
              PackageUpdateInfo(
                name: entry.key,
                currentVersion: current,
                latestVersion: latest,
              ),
            );
          }
        }
      }
      return list;
    } catch (_) {
      return const [];
    }
  }
}

final startupUpdateCheckerProvider = Provider<StartupUpdateChecker>((ref) {
  return DefaultStartupUpdateChecker();
});

class StartupUpdatesNotifier extends StateNotifier<StartupUpdateState> {
  final Ref _ref;

  StartupUpdatesNotifier(this._ref) : super(const StartupUpdateState());

  StartupUpdateChecker get _checker => _ref.read(startupUpdateCheckerProvider);

  Future<void> checkUpdates() async {
    if (state.isChecking) return;
    state = state.copyWith(isChecking: true, error: null);

    try {
      final currentPi = await _checker.checkCurrentPiVersion();
      final latestPi = await _checker.checkLatestPiVersion();

      bool piHasUpdate = false;
      if (currentPi != null && latestPi != null) {
        final curSemVer = SemVer.tryParse(currentPi);
        final latSemVer = SemVer.tryParse(latestPi);
        if (curSemVer != null && latSemVer != null) {
          piHasUpdate = curSemVer.compareTo(latSemVer) < 0;
        } else {
          piHasUpdate = currentPi.trim() != latestPi.trim();
        }
      }

      final outdatedPkgs = await _checker.checkOutdatedPackages();

      state = state.copyWith(
        isChecking: false,
        hasChecked: true,
        piHasUpdate: piHasUpdate,
        currentPiVersion: currentPi,
        latestPiVersion: latestPi,
        outdatedPackages: outdatedPkgs,
      );
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        hasChecked: true,
        error: e.toString(),
      );
    }
  }

  void dismiss() {
    state = state.copyWith(isDismissed: true);
  }
}

final startupUpdatesProvider =
    StateNotifierProvider<StartupUpdatesNotifier, StartupUpdateState>((ref) {
  return StartupUpdatesNotifier(ref);
});

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/update/semver.dart';
import '../daemon/daemon_providers.dart';
import '../platform/platform_environment.dart';

bool hasAvailablePiPackageUpdate(Map<String, dynamic> package) {
  final source = package['source'];
  if (source is! String ||
      source.trim().isEmpty ||
      package['pinnedVersion'] != null ||
      package['updateError'] != null) {
    return false;
  }
  final current = SemVer.tryParse(package['version']?.toString());
  final latest = SemVer.tryParse(package['latestVersion']?.toString());
  return current != null && latest != null && current < latest;
}

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
  final Future<List<Map<String, dynamic>>> Function() listPackages;

  DefaultStartupUpdateChecker({
    required this.listPackages,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  void dispose() => _httpClient.close();

  @override
  Future<String?> checkCurrentPiVersion() async {
    if (kIsWeb) return null;
    final executable = PlatformEnvironment.findExecutable('pi');
    if (executable == null) return null;
    final result = await Process.run(
      executable,
      ['--version'],
      environment: PlatformEnvironment.environment,
      runInShell: Platform.isWindows,
    ).timeout(const Duration(seconds: 4));
    if (result.exitCode != 0) {
      throw StateError('Pi version check failed: ${result.stderr}');
    }
    final version = result.stdout.toString().trim();
    if (SemVer.tryParse(version) == null) {
      throw FormatException('Invalid Pi version: $version');
    }
    return version;
  }

  @override
  Future<String?> checkLatestPiVersion() async {
    final res = await _httpClient
        .get(
          Uri.parse(
            'https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent/latest',
          ),
        )
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) {
      throw StateError('Pi registry check failed: HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final version = data['version']?.toString();
    if (SemVer.tryParse(version) == null) {
      throw FormatException('Invalid Pi registry version: $version');
    }
    return version;
  }

  @override
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async {
    if (kIsWeb) return const [];
    final packages = await listPackages();
    final outdated = <PackageUpdateInfo>[];
    for (final package in packages) {
      final source = package['source']?.toString() ?? '';
      if (!source.startsWith('npm:') || package['pinnedVersion'] != null) {
        continue;
      }
      if (package['updateError'] != null) {
        debugPrint('Package update unavailable: ${package['updateError']}');
        continue;
      }
      final current = package['version']?.toString();
      final latest = package['latestVersion']?.toString();
      final currentVersion = SemVer.tryParse(current);
      final latestVersion = SemVer.tryParse(latest);
      if (currentVersion == null || latestVersion == null) {
        throw StateError(
          'Cannot verify versions for $source. '
          'Restart the daemon after updating PiFrame.',
        );
      }
      if (hasAvailablePiPackageUpdate(package)) {
        outdated.add(
          PackageUpdateInfo(
            name: package['name']?.toString() ?? source,
            currentVersion: current!,
            latestVersion: latest!,
          ),
        );
      }
    }
    return outdated;
  }
}

final startupUpdateCheckerProvider = Provider<StartupUpdateChecker>((ref) {
  final checker = DefaultStartupUpdateChecker(
    listPackages: () async {
      final client = ref.read(pcpClientProvider);
      if (client == null) throw StateError('Daemon disconnected.');
      final result = await client.listPiPackages(checkUpdates: true);
      final data = result['data'] as Map<String, dynamic>? ?? result;
      final packages = data['packages'];
      if (packages is! List) {
        throw const FormatException('Invalid Pi package list.');
      }
      return packages.cast<Map<String, dynamic>>();
    },
  );
  ref.onDispose(checker.dispose);
  return checker;
});

class StartupUpdatesNotifier extends StateNotifier<StartupUpdateState> {
  final Ref _ref;
  Future<void>? _pendingCheck;

  StartupUpdatesNotifier(this._ref) : super(const StartupUpdateState());

  StartupUpdateChecker get _checker => _ref.read(startupUpdateCheckerProvider);

  Future<void> checkUpdates() {
    if (!mounted) return Future.value();
    if (_pendingCheck != null) return _pendingCheck!;
    final check = _checkUpdates();
    _pendingCheck = check;
    return check.whenComplete(() {
      if (identical(_pendingCheck, check)) _pendingCheck = null;
    });
  }

  Future<void> _checkUpdates() async {
    state = state.copyWith(isChecking: true, error: null);
    String? currentPi;
    String? latestPi;
    var outdatedPackages = state.outdatedPackages;
    var piHasUpdate = state.piHasUpdate;
    final errors = <String>[];
    try {
      currentPi = await _checker.checkCurrentPiVersion();
      latestPi = await _checker.checkLatestPiVersion();
      piHasUpdate = _hasNewerVersion(currentPi, latestPi);
    } catch (e) {
      errors.add(e.toString());
    }
    try {
      outdatedPackages = await _checker.checkOutdatedPackages();
    } catch (e) {
      errors.add(e.toString());
    }
    if (!mounted) return;
    final error = errors.isEmpty ? null : errors.join('\n');
    if (error != null) debugPrint('Startup update check failed: $error');
    state = StartupUpdateState(
      hasChecked: true,
      piHasUpdate: piHasUpdate,
      currentPiVersion: currentPi,
      latestPiVersion: latestPi,
      outdatedPackages: outdatedPackages,
      isDismissed: state.isDismissed,
      error: error,
    );
  }

  bool _hasNewerVersion(String? current, String? latest) {
    if (current == null || latest == null) return false;
    return SemVer.parse(current) < SemVer.parse(latest);
  }

  Future<void> refreshPackages() {
    if (!mounted) return Future.value();
    final refresh = (_pendingCheck ?? Future<void>.value()).then<void>((
      _,
    ) async {
      if (!mounted) return;
      await _refreshPackages();
    });
    _pendingCheck = refresh;
    return refresh.whenComplete(() {
      if (identical(_pendingCheck, refresh)) _pendingCheck = null;
    });
  }

  Future<void> _refreshPackages() async {
    state = state.copyWith(isChecking: true);
    try {
      final packages = await _checker.checkOutdatedPackages();
      if (!mounted) return;
      state = state.copyWith(
        isChecking: false,
        hasChecked: true,
        outdatedPackages: packages,
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('Package update check failed: $error');
      state = state.copyWith(
        isChecking: false,
        hasChecked: true,
        error: error.toString(),
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

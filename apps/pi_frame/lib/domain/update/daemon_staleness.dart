import 'semver.dart';

/// Whether the daemon that is running must be replaced by the one this app ships.
///
/// An older version is stale. A daemon of the same version is stale when the daemon file this app would launch
/// ([sidecarBuiltAt]) was written after that daemon started: a rebuild or an update that kept the version number
/// left the previous build running. A newer version is never replaced, so two installed versions of the app do
/// not restart each other's daemon.
bool isRunningDaemonStale({
  required String appVersion,
  required String? runningVersion,
  required DateTime? runningStartedAt,
  DateTime? sidecarBuiltAt,
}) {
  final app = SemVer.tryParse(appVersion);
  final running = SemVer.tryParse(runningVersion);
  if (app == null || running == null) return false;
  final order = running.compareTo(app);
  if (order < 0) return true;
  if (order > 0) return false;
  return runningStartedAt != null && sidecarBuiltAt != null && sidecarBuiltAt.isAfter(runningStartedAt);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/runtime/app_version.dart';
import '../../data/changelog/changelog_service.dart';
import '../../data/platform/host_environment_service.dart';
import '../../data/changelog/changelog_store.dart';
import 'changelog_dialog.dart';

/// Invisible watcher mounted in the root [AppShell].
///
/// On startup after an update, checks whether the changelog popup should be
/// shown for the current app version. If so, loads the changelog highlights
/// (features and bug fixes only) and displays the [ChangelogDialog].
class StartupChangelogWatcher extends ConsumerStatefulWidget {
  final bool enableInTests;

  const StartupChangelogWatcher({super.key, this.enableInTests = false});

  @override
  ConsumerState<StartupChangelogWatcher> createState() => _StartupChangelogWatcherState();
}

class _StartupChangelogWatcherState extends ConsumerState<StartupChangelogWatcher> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkChangelog();
    });
  }

  Future<void> _checkChangelog() async {
    if (_checked) return;
    _checked = true;

    final host = ref.read(hostEnvironmentServiceProvider);
    final inTest = !host.isWeb && host.variable('FLUTTER_TEST') != null;
    if (inTest && !widget.enableInTests) {
      return;
    }

    final store = ref.read(changelogStoreProvider);
    final shouldShow = store.shouldShowChangelog(piFrameVersion);
    if (!shouldShow || !mounted) return;

    final service = ref.read(changelogServiceProvider);
    final release = await service.loadRelease(version: piFrameVersion);

    if (!mounted) return;

    // Persist current version as seen so the popup is never shown twice for this release
    store.setLastSeenVersion(piFrameVersion);

    if (release != null && release.isNotEmpty && mounted) {
      await showChangelogDialog(context: context, release: release);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

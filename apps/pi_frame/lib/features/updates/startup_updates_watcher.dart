import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/platform/host_environment_service.dart';
import '../../data/update/startup_updates_provider.dart';

class StartupUpdatesWatcher extends ConsumerStatefulWidget {
  const StartupUpdatesWatcher({super.key});

  @override
  ConsumerState<StartupUpdatesWatcher> createState() => _StartupUpdatesWatcherState();
}

class _StartupUpdatesWatcherState extends ConsumerState<StartupUpdatesWatcher> {
  bool _requested = false;

  void _checkWhenConnected(AsyncValue<DaemonConnectionState> connection) {
    if (connection.value != DaemonConnectionState.connected) {
      _requested = false;
      return;
    }
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(startupUpdatesProvider.notifier).checkUpdates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(hostEnvironmentServiceProvider);
    if (!host.isWeb && host.variable('FLUTTER_TEST') == null) {
      ref.listen(connectionStateProvider, (_, next) => _checkWhenConnected(next));
      _checkWhenConnected(ref.watch(connectionStateProvider));
    }
    return const SizedBox.shrink();
  }
}

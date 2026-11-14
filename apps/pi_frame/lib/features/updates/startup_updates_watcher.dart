import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/update/startup_updates_provider.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';

class StartupUpdatesWatcher extends ConsumerStatefulWidget {
  const StartupUpdatesWatcher({super.key});

  @override
  ConsumerState<StartupUpdatesWatcher> createState() =>
      _StartupUpdatesWatcherState();
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
    if (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')) {
      ref.listen(
        connectionStateProvider,
        (_, next) => _checkWhenConnected(next),
      );
      _checkWhenConnected(ref.watch(connectionStateProvider));
    }
    return const SizedBox.shrink();
  }
}

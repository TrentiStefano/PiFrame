import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/update/startup_updates_provider.dart';

class StartupUpdatesWatcher extends ConsumerStatefulWidget {
  const StartupUpdatesWatcher({super.key});

  @override
  ConsumerState<StartupUpdatesWatcher> createState() =>
      _StartupUpdatesWatcherState();
}

class _StartupUpdatesWatcherState extends ConsumerState<StartupUpdatesWatcher> {
  @override
  void initState() {
    super.initState();
    // Do not launch unattended shell commands in tests that mount AppShell
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(startupUpdatesProvider.notifier).checkUpdates();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

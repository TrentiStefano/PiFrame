import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/update/update_providers.dart';

class UpdatesPeriodicWatcher extends ConsumerStatefulWidget {
  const UpdatesPeriodicWatcher({super.key});

  @override
  ConsumerState<UpdatesPeriodicWatcher> createState() =>
      _UpdatesPeriodicWatcherState();
}

class _UpdatesPeriodicWatcherState
    extends ConsumerState<UpdatesPeriodicWatcher> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfDue();
    });
    // Check every hour if periodic interval is due
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkIfDue();
    });
  }

  void _checkIfDue() {
    if (!mounted) return;
    final settings = ref.read(updateSettingsProvider);
    if (settings.shouldCheckNow(DateTime.now())) {
      ref.read(updateControllerProvider.notifier).checkForUpdates(isManual: false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

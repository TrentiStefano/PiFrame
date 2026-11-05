import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nerd_stats_settings.dart';

class FpsNotifier extends StateNotifier<int> {
  final Ref _ref;
  Timer? _windowTimer;
  TimingsCallback? _timingsCallback;
  int _framesInCurrentWindow = 0;
  bool _registered = false;

  bool get isRegistered => _registered;

  FpsNotifier(this._ref) : super(0) {
    _init();
  }

  void _init() {
    _ref.listen<NerdStatsSettings>(
      nerdStatsSettingsProvider,
      (prev, next) => _evaluateRegistration(),
    );
    _evaluateRegistration();
  }

  void _evaluateRegistration() {
    final enabled = _ref.read(nerdStatsSettingsProvider).enabled;
    if (enabled && !_registered) {
      _start();
    } else if (!enabled && _registered) {
      _stop();
    }
  }

  void _start() {
    _registered = true;
    _framesInCurrentWindow = 0;
    _timingsCallback = (List<FrameTiming> timings) {
      _framesInCurrentWindow += timings.length;
    };
    try {
      SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
    } catch (_) {
      // In unit test environments without initialized SchedulerBinding
    }

    _windowTimer?.cancel();
    _windowTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentFps = _framesInCurrentWindow;
      _framesInCurrentWindow = 0;
      if (mounted && state != currentFps) {
        state = currentFps;
      }
    });
  }

  void _stop() {
    _registered = false;
    _windowTimer?.cancel();
    _windowTimer = null;
    if (_timingsCallback != null) {
      try {
        SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
      } catch (_) {}
      _timingsCallback = null;
    }
    _framesInCurrentWindow = 0;
    if (mounted) {
      state = 0;
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

final fpsProvider = StateNotifierProvider<FpsNotifier, int>((ref) {
  return FpsNotifier(ref);
});

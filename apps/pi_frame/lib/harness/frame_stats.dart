/// Frame timing statistics for the harness `frames` command (#118): build and raster percentiles and the frames
/// that missed a 60 Hz frame budget. Pure: the harness extension collects [FrameSample]s from
/// `SchedulerBinding.addTimingsCallback` and returns [FrameStats.toJson].
library;

import 'dart:math' as math;

/// The time one 60 Hz frame may take, in milliseconds.
const double frameBudgetMs = 1000 / 60;

/// One rendered frame: the time the UI thread spent building it and the raster thread spent drawing it.
class FrameSample {
  final Duration build;
  final Duration raster;

  const FrameSample({required this.build, required this.raster});
}

class FrameStats {
  final int count;
  final double buildP50Ms;
  final double buildP90Ms;
  final double rasterP50Ms;
  final double rasterP90Ms;
  final double worstTotalMs;

  /// Frames whose build or raster time alone exceeded [frameBudgetMs].
  final int overBudget;

  const FrameStats({
    required this.count,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.worstTotalMs,
    required this.overBudget,
  });

  factory FrameStats.of(List<FrameSample> frames) {
    double ms(Duration d) => d.inMicroseconds / Duration.microsecondsPerMillisecond;
    final build = frames.map((f) => ms(f.build)).toList()..sort();
    final raster = frames.map((f) => ms(f.raster)).toList()..sort();
    return FrameStats(
      count: frames.length,
      buildP50Ms: _percentile(build, 50),
      buildP90Ms: _percentile(build, 90),
      rasterP50Ms: _percentile(raster, 50),
      rasterP90Ms: _percentile(raster, 90),
      worstTotalMs: frames.fold(0.0, (worst, f) => math.max(worst, ms(f.build) + ms(f.raster))),
      overBudget: frames.where((f) => ms(f.build) > frameBudgetMs || ms(f.raster) > frameBudgetMs).length,
    );
  }

  Map<String, Object> toJson() => {
    'count': count,
    'buildP50Ms': buildP50Ms,
    'buildP90Ms': buildP90Ms,
    'rasterP50Ms': rasterP50Ms,
    'rasterP90Ms': rasterP90Ms,
    'worstTotalMs': worstTotalMs,
    'overBudget': overBudget,
    'budgetMs': frameBudgetMs,
  };
}

/// The nearest-rank percentile of an ascending list, or 0 for an empty one.
double _percentile(List<double> sorted, int percent) {
  if (sorted.isEmpty) return 0;
  final rank = (percent / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

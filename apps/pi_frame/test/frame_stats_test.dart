import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/harness/frame_stats.dart';

void main() {
  // #118: a lag report needs a number that is red before a fix and green after it.
  test('summarises build and raster times as percentiles and counts frames over budget', () {
    final frames = [
      for (var i = 1; i <= 10; i++)
        FrameSample(
          build: Duration(milliseconds: i),
          raster: Duration(milliseconds: i * 2),
        ),
    ];
    final stats = FrameStats.of(frames);
    expect(stats.count, 10);
    expect(stats.buildP50Ms, 5);
    expect(stats.buildP90Ms, 9);
    expect(stats.rasterP90Ms, 18);
    expect(stats.worstTotalMs, 30);
    // A frame is over budget when build or raster alone takes longer than 16.7 ms (60 Hz).
    expect(stats.overBudget, 2);
    expect(stats.toJson()['overBudget'], 2);
  });

  test('no frames gives zeros, not an error', () {
    final stats = FrameStats.of(const []);
    expect(stats.count, 0);
    expect(stats.buildP90Ms, 0);
    expect(stats.overBudget, 0);
  });
}

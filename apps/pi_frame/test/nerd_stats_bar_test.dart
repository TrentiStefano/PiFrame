import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/metrics/fps_counter.dart';
import 'package:pi_frame/data/metrics/nerd_stats_settings.dart';
import 'package:pi_frame/data/metrics/system_metrics_controller.dart';
import 'package:pi_frame/data/metrics/system_metrics_model.dart';
import 'package:pi_frame/features/metrics/nerd_stats_bar.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

Widget _buildTestWidget({
  required List<Override> overrides,
  double width = 1000,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [FrameTokens.dark],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: NerdStatsBar(width: width),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('NerdStatsBar widget', () {
    testWidgets('hidden when setting is OFF', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(false),
            ),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('nerd-stats-bar')), findsNothing);
    });

    testWidgets('shows formatted metric values and FPS when ON', (
      tester,
    ) async {
      const metrics = SystemMetricsData(
        cpuPercent: 12.3,
        memoryPercent: 48.0,
        memoryUsedBytes: 8589934592,
        memoryTotalBytes: 17179869184,
        diskPercent: 62.0,
        diskUsedBytes: 256000000000,
        diskTotalBytes: 512000000000,
        gpuPercent: null, // null GPU -> n/d
        isStale: false,
        hasCapability: true,
      );

      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            isWebProvider.overrideWithValue(false),
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(true),
            ),
            systemMetricsProvider.overrideWith(
              (ref) => SystemMetricsController(ref)..state = metrics,
            ),
            fpsProvider.overrideWith((ref) => FpsNotifier(ref)..state = 60),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('nerd-stats-bar')), findsOneWidget);

      // Verify the exact rendered monospace string
      expect(
        find.text('CPU 12.3% · RAM 48% · DISK 62% · GPU n/d · 60 FPS'),
        findsOneWidget,
      );
    });

    testWidgets('shows GPU percentage when available', (tester) async {
      const metrics = SystemMetricsData(
        cpuPercent: 10.0,
        memoryPercent: 30.0,
        diskPercent: 40.0,
        gpuPercent: 15.0,
        isStale: false,
        hasCapability: true,
      );

      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            isWebProvider.overrideWithValue(false),
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(true),
            ),
            systemMetricsProvider.overrideWith(
              (ref) => SystemMetricsController(ref)..state = metrics,
            ),
            fpsProvider.overrideWith((ref) => FpsNotifier(ref)..state = 58),
          ],
        ),
      );

      expect(
        find.text('CPU 10.0% · RAM 30% · DISK 40% · GPU 15% · 58 FPS'),
        findsOneWidget,
      );
    });

    testWidgets('web mode shows ONLY the FPS segment', (tester) async {
      const metrics = SystemMetricsData(
        cpuPercent: 12.3,
        memoryPercent: 48.0,
        diskPercent: 62.0,
        gpuPercent: 15.0,
        isStale: false,
        hasCapability: true,
      );

      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            isWebProvider.overrideWithValue(true),
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(true),
            ),
            systemMetricsProvider.overrideWith(
              (ref) => SystemMetricsController(ref)..state = metrics,
            ),
            fpsProvider.overrideWith((ref) => FpsNotifier(ref)..state = 60),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('nerd-stats-bar')), findsOneWidget);
      expect(find.text('60 FPS'), findsOneWidget);
      expect(find.textContaining('CPU'), findsNothing);
      expect(find.textContaining('RAM'), findsNothing);
      expect(find.textContaining('DISK'), findsNothing);
      expect(find.textContaining('GPU'), findsNothing);
    });

    testWidgets('hides gracefully when width is below threshold', (
      tester,
    ) async {
      const metrics = SystemMetricsData(
        cpuPercent: 12.3,
        memoryPercent: 48.0,
        diskPercent: 62.0,
        isStale: false,
        hasCapability: true,
      );

      // Width below 760 on desktop
      await tester.pumpWidget(
        _buildTestWidget(
          width: 700,
          overrides: [
            isWebProvider.overrideWithValue(false),
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(true),
            ),
            systemMetricsProvider.overrideWith(
              (ref) => SystemMetricsController(ref)..state = metrics,
            ),
            fpsProvider.overrideWith((ref) => FpsNotifier(ref)..state = 60),
          ],
        ),
      );

      expect(find.byKey(const ValueKey('nerd-stats-bar')), findsNothing);
    });

    testWidgets('shows warning color for metrics above 85%', (tester) async {
      const metrics = SystemMetricsData(
        cpuPercent: 92.0,
        memoryPercent: 50.0,
        diskPercent: 40.0,
        gpuPercent: 10.0,
        isStale: false,
        hasCapability: true,
      );

      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            isWebProvider.overrideWithValue(false),
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(true),
            ),
            systemMetricsProvider.overrideWith(
              (ref) => SystemMetricsController(ref)..state = metrics,
            ),
            fpsProvider.overrideWith((ref) => FpsNotifier(ref)..state = 60),
          ],
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      final rootSpan = textWidget.textSpan as TextSpan?;
      expect(rootSpan, isNotNull);

      // Find the CPU value span
      final cpuSpan = rootSpan!.children!.firstWhere(
        (span) => span is TextSpan && span.text == '92.0%',
      ) as TextSpan;

      expect(cpuSpan.style?.color, equals(FrameTokens.dark.warning));
    });

    testWidgets('tooltip contains full details and formatted bytes', (
      tester,
    ) async {
      const metrics = SystemMetricsData(
        cpuPercent: 12.3,
        memoryUsedBytes: 8589934592,
        memoryTotalBytes: 17179869184,
        memoryPercent: 50.0,
        diskUsedBytes: 256000000000,
        diskTotalBytes: 512000000000,
        diskPercent: 50.0,
        gpuPercent: 35.5,
        gpuMemoryUsedBytes: 4294967296,
        gpuMemoryTotalBytes: 8589934592,
        gpuSource: 'nvidia-smi',
        isStale: false,
        hasCapability: true,
      );

      await tester.pumpWidget(
        _buildTestWidget(
          overrides: [
            isWebProvider.overrideWithValue(false),
            nerdStatsSettingsProvider.overrideWith(
              (ref) => NerdStatsSettingsNotifier()..setEnabled(true),
            ),
            systemMetricsProvider.overrideWith(
              (ref) => SystemMetricsController(ref)..state = metrics,
            ),
            fpsProvider.overrideWith((ref) => FpsNotifier(ref)..state = 60),
          ],
        ),
      );

      final tooltipWidget = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltipWidget.message, contains('CPU: 12.3%'));
      expect(tooltipWidget.message, contains('RAM: 8.0 GB / 16.0 GB (50%)'));
      expect(tooltipWidget.message, contains('Disk: 238.4 GB / 476.8 GB (50%)'));
      expect(tooltipWidget.message, contains('GPU: 35.5% · VRAM: 4.0 GB / 8.0 GB (source: nvidia-smi)'));
      expect(tooltipWidget.message, contains('Render: 60 FPS'));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
import '../../data/metrics/fps_counter.dart';
import '../../data/metrics/nerd_stats_settings.dart';
import '../../data/metrics/system_metrics_controller.dart';
import '../../data/metrics/system_metrics_model.dart';

class NerdStatsBar extends ConsumerWidget {
  final double? width;

  const NerdStatsBar({super.key, this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(nerdStatsSettingsProvider);
    if (!settings.enabled) return const SizedBox.shrink();

    final isWeb = ref.watch(isWebProvider);
    if (width != null && width! < (isWeb ? 450 : 760)) {
      return const SizedBox.shrink();
    }

    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final metrics = isWeb ? null : ref.watch(systemMetricsProvider);
    final fps = ref.watch(fpsProvider);

    final isStaleOrUnavailable =
        metrics == null || metrics.isStale || !metrics.hasCapability;

    final tooltip = buildNerdStatsTooltip(
      isWeb: isWeb,
      metrics: metrics,
      fps: fps,
    );

    final cpuVal = isStaleOrUnavailable ? null : metrics.cpuPercent;
    final ramVal = isStaleOrUnavailable ? null : metrics.memoryPercent;
    final diskVal = isStaleOrUnavailable ? null : metrics.diskPercent;
    final gpuVal = isStaleOrUnavailable ? null : metrics.gpuPercent;

    final notAvailableStr = strings.nerdStatsNotAvailable;
    final cpuStr = isStaleOrUnavailable || metrics.cpuPercent == null
        ? notAvailableStr
        : formatCpuPercent(metrics.cpuPercent);
    final ramStr = isStaleOrUnavailable || metrics.memoryPercent == null
        ? notAvailableStr
        : formatResourcePercent(metrics.memoryPercent);
    final diskStr = isStaleOrUnavailable || metrics.diskPercent == null
        ? notAvailableStr
        : formatResourcePercent(metrics.diskPercent);
    final gpuStr = isStaleOrUnavailable || metrics.gpuPercent == null
        ? notAvailableStr
        : formatResourcePercent(metrics.gpuPercent);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        key: const ValueKey('nerd-stats-bar'),
        padding: const EdgeInsets.symmetric(
          horizontal: FrameSpace.x2,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
        ),
        child: isWeb
            ? Text(
                '$fps FPS',
                style: FrameText.of(context).mono
                    .copyWith(color: tokens.textSecondary),
              )
            : Text.rich(
                TextSpan(
                  style: FrameText.of(context).mono
                      .copyWith(color: tokens.textSecondary),
                  children: [
                    TextSpan(
                      text: 'CPU ',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                    TextSpan(
                      text: cpuStr,
                      style: TextStyle(
                        color: cpuVal != null && cpuVal > 85.0
                            ? tokens.warning
                            : tokens.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: ' · ',
                      style: TextStyle(
                        color: tokens.textMuted.withValues(alpha: 0.45),
                      ),
                    ),
                    TextSpan(
                      text: 'RAM ',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                    TextSpan(
                      text: ramStr,
                      style: TextStyle(
                        color: ramVal != null && ramVal > 85.0
                            ? tokens.warning
                            : tokens.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: ' · ',
                      style: TextStyle(
                        color: tokens.textMuted.withValues(alpha: 0.45),
                      ),
                    ),
                    TextSpan(
                      text: 'DISK ',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                    TextSpan(
                      text: diskStr,
                      style: TextStyle(
                        color: diskVal != null && diskVal > 85.0
                            ? tokens.warning
                            : tokens.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: ' · ',
                      style: TextStyle(
                        color: tokens.textMuted.withValues(alpha: 0.45),
                      ),
                    ),
                    TextSpan(
                      text: 'GPU ',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                    TextSpan(
                      text: gpuStr,
                      style: TextStyle(
                        color: gpuVal != null && gpuVal > 85.0
                            ? tokens.warning
                            : tokens.textSecondary,
                      ),
                    ),
                    TextSpan(
                      text: ' · ',
                      style: TextStyle(
                        color: tokens.textMuted.withValues(alpha: 0.45),
                      ),
                    ),
                    TextSpan(
                      text: '$fps FPS',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

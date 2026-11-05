import 'package:flutter/foundation.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

String formatBytes(int? bytes) {
  if (bytes == null) return 'n/d';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024.0;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024.0;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024.0;
  return '${gb.toStringAsFixed(1)} GB';
}

String formatCpuPercent(double? percent) {
  if (percent == null) return 'n/d';
  return '${percent.toStringAsFixed(1)}%';
}

String formatResourcePercent(double? percent) {
  if (percent == null) return 'n/d';
  if ((percent - percent.roundToDouble()).abs() < 0.05) {
    return '${percent.round()}%';
  }
  return '${percent.toStringAsFixed(1)}%';
}

String buildNerdStatsTooltip({
  required bool isWeb,
  required SystemMetricsData? metrics,
  required int fps,
}) {
  if (isWeb) {
    return 'Render: $fps FPS';
  }
  final isStaleOrUnavailable =
      metrics == null || metrics.isStale || !metrics.hasCapability;

  final cpu = !isStaleOrUnavailable && metrics.cpuPercent != null
      ? formatCpuPercent(metrics.cpuPercent)
      : 'n/d';

  final ramUsed = !isStaleOrUnavailable && metrics.memoryUsedBytes != null
      ? formatBytes(metrics.memoryUsedBytes)
      : 'n/d';
  final ramTotal = !isStaleOrUnavailable && metrics.memoryTotalBytes != null
      ? formatBytes(metrics.memoryTotalBytes)
      : 'n/d';
  final ramPct = !isStaleOrUnavailable && metrics.memoryPercent != null
      ? formatResourcePercent(metrics.memoryPercent)
      : 'n/d';
  final ram = (ramUsed == 'n/d' && ramTotal == 'n/d' && ramPct == 'n/d')
      ? 'n/d'
      : '$ramUsed / $ramTotal ($ramPct)';

  final diskUsed = !isStaleOrUnavailable && metrics.diskUsedBytes != null
      ? formatBytes(metrics.diskUsedBytes)
      : 'n/d';
  final diskTotal = !isStaleOrUnavailable && metrics.diskTotalBytes != null
      ? formatBytes(metrics.diskTotalBytes)
      : 'n/d';
  final diskPct = !isStaleOrUnavailable && metrics.diskPercent != null
      ? formatResourcePercent(metrics.diskPercent)
      : 'n/d';
  final disk = (diskUsed == 'n/d' && diskTotal == 'n/d' && diskPct == 'n/d')
      ? 'n/d'
      : '$diskUsed / $diskTotal ($diskPct)';

  final gpuPct = !isStaleOrUnavailable && metrics.gpuPercent != null
      ? formatResourcePercent(metrics.gpuPercent)
      : 'n/d';
  final gpuVram = !isStaleOrUnavailable &&
          (metrics.gpuMemoryUsedBytes != null ||
              metrics.gpuMemoryTotalBytes != null)
      ? ' · VRAM: ${formatBytes(metrics.gpuMemoryUsedBytes)} / ${formatBytes(metrics.gpuMemoryTotalBytes)}'
      : '';
  final gpuSource = !isStaleOrUnavailable && metrics.gpuSource != null
      ? ' (source: ${metrics.gpuSource})'
      : '';
  final gpu = (gpuPct == 'n/d' && gpuVram.isEmpty && gpuSource.isEmpty)
      ? 'n/d'
      : '$gpuPct$gpuVram$gpuSource';

  return 'CPU: $cpu\nRAM: $ram\nDisk: $disk\nGPU: $gpu\nRender: $fps FPS';
}

@immutable
class SystemMetricsData {
  final int? sampledAt;
  final double? cpuPercent;
  final int? memoryUsedBytes;
  final int? memoryTotalBytes;
  final double? memoryPercent;
  final int? diskUsedBytes;
  final int? diskTotalBytes;
  final double? diskPercent;
  final double? gpuPercent;
  final int? gpuMemoryUsedBytes;
  final int? gpuMemoryTotalBytes;
  final String? gpuSource;
  final bool isStale;
  final bool hasCapability;

  const SystemMetricsData({
    this.sampledAt,
    this.cpuPercent,
    this.memoryUsedBytes,
    this.memoryTotalBytes,
    this.memoryPercent,
    this.diskUsedBytes,
    this.diskTotalBytes,
    this.diskPercent,
    this.gpuPercent,
    this.gpuMemoryUsedBytes,
    this.gpuMemoryTotalBytes,
    this.gpuSource,
    this.isStale = false,
    this.hasCapability = true,
  });

  const SystemMetricsData.empty({
    this.hasCapability = true,
    this.isStale = false,
  })  : sampledAt = null,
        cpuPercent = null,
        memoryUsedBytes = null,
        memoryTotalBytes = null,
        memoryPercent = null,
        diskUsedBytes = null,
        diskTotalBytes = null,
        diskPercent = null,
        gpuPercent = null,
        gpuMemoryUsedBytes = null,
        gpuMemoryTotalBytes = null,
        gpuSource = null;

  factory SystemMetricsData.fromMap(
    Map<String, dynamic> map, {
    bool hasCapability = true,
  }) {
    final cpu = map['cpu'] as Map<String, dynamic>?;
    final mem = map['memory'] as Map<String, dynamic>?;
    final disk = map['disk'] as Map<String, dynamic>?;
    final gpu = map['gpu'] as Map<String, dynamic>?;

    return SystemMetricsData(
      sampledAt: (map['sampledAt'] as num?)?.toInt(),
      cpuPercent: (cpu?['percent'] as num?)?.toDouble(),
      memoryUsedBytes: (mem?['usedBytes'] as num?)?.toInt(),
      memoryTotalBytes: (mem?['totalBytes'] as num?)?.toInt(),
      memoryPercent: (mem?['percent'] as num?)?.toDouble(),
      diskUsedBytes: (disk?['usedBytes'] as num?)?.toInt(),
      diskTotalBytes: (disk?['totalBytes'] as num?)?.toInt(),
      diskPercent: (disk?['percent'] as num?)?.toDouble(),
      gpuPercent: (gpu?['percent'] as num?)?.toDouble(),
      gpuMemoryUsedBytes: (gpu?['memoryUsedBytes'] as num?)?.toInt(),
      gpuMemoryTotalBytes: (gpu?['memoryTotalBytes'] as num?)?.toInt(),
      gpuSource: gpu?['source'] as String?,
      isStale: false,
      hasCapability: hasCapability,
    );
  }

  factory SystemMetricsData.fromEvent(
    SystemMetricsEvent event, {
    bool hasCapability = true,
  }) {
    return SystemMetricsData.fromMap(
      event.payload,
      hasCapability: hasCapability,
    );
  }

  SystemMetricsData copyWith({
    int? sampledAt,
    double? cpuPercent,
    int? memoryUsedBytes,
    int? memoryTotalBytes,
    double? memoryPercent,
    int? diskUsedBytes,
    int? diskTotalBytes,
    double? diskPercent,
    double? gpuPercent,
    int? gpuMemoryUsedBytes,
    int? gpuMemoryTotalBytes,
    String? gpuSource,
    bool? isStale,
    bool? hasCapability,
  }) {
    return SystemMetricsData(
      sampledAt: sampledAt ?? this.sampledAt,
      cpuPercent: cpuPercent ?? this.cpuPercent,
      memoryUsedBytes: memoryUsedBytes ?? this.memoryUsedBytes,
      memoryTotalBytes: memoryTotalBytes ?? this.memoryTotalBytes,
      memoryPercent: memoryPercent ?? this.memoryPercent,
      diskUsedBytes: diskUsedBytes ?? this.diskUsedBytes,
      diskTotalBytes: diskTotalBytes ?? this.diskTotalBytes,
      diskPercent: diskPercent ?? this.diskPercent,
      gpuPercent: gpuPercent ?? this.gpuPercent,
      gpuMemoryUsedBytes: gpuMemoryUsedBytes ?? this.gpuMemoryUsedBytes,
      gpuMemoryTotalBytes: gpuMemoryTotalBytes ?? this.gpuMemoryTotalBytes,
      gpuSource: gpuSource ?? this.gpuSource,
      isStale: isStale ?? this.isStale,
      hasCapability: hasCapability ?? this.hasCapability,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemMetricsData &&
          runtimeType == other.runtimeType &&
          sampledAt == other.sampledAt &&
          cpuPercent == other.cpuPercent &&
          memoryUsedBytes == other.memoryUsedBytes &&
          memoryTotalBytes == other.memoryTotalBytes &&
          memoryPercent == other.memoryPercent &&
          diskUsedBytes == other.diskUsedBytes &&
          diskTotalBytes == other.diskTotalBytes &&
          diskPercent == other.diskPercent &&
          gpuPercent == other.gpuPercent &&
          gpuMemoryUsedBytes == other.gpuMemoryUsedBytes &&
          gpuMemoryTotalBytes == other.gpuMemoryTotalBytes &&
          gpuSource == other.gpuSource &&
          isStale == other.isStale &&
          hasCapability == other.hasCapability;

  @override
  int get hashCode => Object.hash(
        sampledAt,
        cpuPercent,
        memoryUsedBytes,
        memoryTotalBytes,
        memoryPercent,
        diskUsedBytes,
        diskTotalBytes,
        diskPercent,
        gpuPercent,
        gpuMemoryUsedBytes,
        gpuMemoryTotalBytes,
        gpuSource,
        isStale,
        hasCapability,
      );

  @override
  String toString() =>
      'SystemMetricsData(cpu: $cpuPercent%, memory: $memoryPercent%, disk: $diskPercent%, gpu: $gpuPercent% [$gpuSource], isStale: $isStale, hasCap: $hasCapability)';
}

/// Semantic tone for the context-usage indicator.
///
/// Muted is the normal state. Warning starts at [kContextWarningPercent].
/// Danger starts at [kContextDangerPercent], or at the compaction threshold
/// when the configured compaction reserve puts it lower.
library;

enum ContextUsageTone { muted, warning, danger }

const double kContextWarningPercent = 70;
const double kContextDangerPercent = 90;

ContextUsageTone contextUsageTone(
  double percent, {
  double? compactionReservePercent,
}) {
  var dangerAt = kContextDangerPercent;
  if (compactionReservePercent != null) {
    final compactionAt = 100 - compactionReservePercent;
    if (compactionAt < dangerAt) dangerAt = compactionAt;
  }
  if (percent >= dangerAt) return ContextUsageTone.danger;
  if (percent >= kContextWarningPercent) return ContextUsageTone.warning;
  return ContextUsageTone.muted;
}

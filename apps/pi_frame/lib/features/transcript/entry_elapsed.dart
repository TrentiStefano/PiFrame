import '../../domain/session/session_state.dart';

/// Shortest gap shown as an elapsed chip, in milliseconds.
const int kEntryElapsedMinGapMs = 5000;

/// Longest gap that still counts as one turn. Larger gaps come from stale or
/// non-message timestamps and are never shown.
const int kEntryElapsedMaxGapMs = 24 * 60 * 60 * 1000;

/// Whether an entry with [role] can anchor an elapsed time.
bool isEntryElapsedAnchor(String role) => role == 'user' || role == 'assistant';

/// Seconds between the entry at [index] and its nearest preceding user or
/// assistant entry. Other entries (summaries, custom, bash output) are skipped.
///
/// Returns null when there is no such predecessor, when the gap is under
/// [kEntryElapsedMinGapMs], or when it is over [kEntryElapsedMaxGapMs].
int? entryElapsedSeconds(List<SessionEntry> entries, int index) {
  if (index <= 0 || index >= entries.length) return null;
  final currentMs = entries[index].timestamp;
  for (var i = index - 1; i >= 0; i--) {
    final candidate = entries[i];
    if (!isEntryElapsedAnchor(candidate.role)) continue;
    final gapMs = currentMs - candidate.timestamp;
    if (gapMs < kEntryElapsedMinGapMs || gapMs > kEntryElapsedMaxGapMs) {
      return null;
    }
    return (gapMs / 1000).round();
  }
  return null;
}

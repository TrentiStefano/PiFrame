import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/entry_elapsed.dart';

SessionEntry _entry(String id, String role, int timestamp) => SessionEntry(
      id: id,
      role: role,
      text: id,
      timestamp: timestamp,
    );

void main() {
  group('entryElapsedSeconds', () {
    test('returns null for the first entry and out-of-range indexes', () {
      final entries = [_entry('u1', 'user', 0)];

      expect(entryElapsedSeconds(entries, 0), isNull);
      expect(entryElapsedSeconds(entries, -1), isNull);
      expect(entryElapsedSeconds(entries, 1), isNull);
    });

    test('measures from a preceding user entry', () {
      final entries = [
        _entry('u1', 'user', 0),
        _entry('a1', 'assistant', 12000),
      ];

      expect(entryElapsedSeconds(entries, 1), 12);
    });

    test('measures from a preceding assistant entry', () {
      final entries = [
        _entry('a0', 'assistant', 0),
        _entry('u1', 'user', 30000),
        _entry('a1', 'assistant', 41000),
      ];

      expect(entryElapsedSeconds(entries, 2), 11);
    });

    test('skips non-message predecessors and uses the nearest user or assistant', () {
      // A compaction summary written long before the turn must not be the anchor.
      final entries = [
        _entry('u1', 'user', 1000000),
        _entry('s1', 'compactionSummary', 1000),
        _entry('c1', 'custom', 2000),
        _entry('a1', 'assistant', 1000000 + 9000),
      ];

      expect(entryElapsedSeconds(entries, 3), 9);
    });

    test('returns null when no user or assistant predecessor exists', () {
      final entries = [
        _entry('s1', 'branchSummary', 0),
        _entry('c1', 'custom', 1000),
        _entry('a1', 'assistant', 60000),
      ];

      expect(entryElapsedSeconds(entries, 2), isNull);
    });

    test('hides gaps under 5 seconds and shows exactly 5 seconds', () {
      final under = [_entry('u1', 'user', 0), _entry('a1', 'assistant', 4999)];
      final exact = [_entry('u1', 'user', 0), _entry('a1', 'assistant', 5000)];

      expect(entryElapsedSeconds(under, 1), isNull);
      expect(entryElapsedSeconds(exact, 1), 5);
    });

    test('shows a gap of exactly 24 hours and hides anything longer', () {
      const dayMs = 24 * 60 * 60 * 1000;
      expect(kEntryElapsedMaxGapMs, dayMs);

      final atLimit = [_entry('u1', 'user', 0), _entry('a1', 'assistant', dayMs)];
      final overLimit = [
        _entry('u1', 'user', 0),
        _entry('a1', 'assistant', dayMs + 1),
      ];

      expect(entryElapsedSeconds(atLimit, 1), 86400);
      expect(entryElapsedSeconds(overLimit, 1), isNull);
    });

    test('hides a stale predecessor timestamp even when a closer summary is skipped', () {
      // Regression: a summary with an old timestamp used to produce "944953012s".
      final entries = [
        _entry('u1', 'user', 0),
        _entry('s1', 'compactionSummary', 1),
        _entry('a1', 'assistant', 944953012 * 1000),
      ];

      expect(entryElapsedSeconds(entries, 2), isNull);
    });

    test('returns null when the entry is older than its predecessor', () {
      final entries = [_entry('u1', 'user', 10000), _entry('a1', 'assistant', 1000)];

      expect(entryElapsedSeconds(entries, 1), isNull);
    });
  });
}

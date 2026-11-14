import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/context_usage_tone.dart';

void main() {
  group('contextUsageTone', () {
    test('uses muted below 70 percent and warning from 70 percent', () {
      expect(contextUsageTone(0), ContextUsageTone.muted);
      expect(contextUsageTone(69), ContextUsageTone.muted);
      expect(contextUsageTone(69.9), ContextUsageTone.muted);
      expect(contextUsageTone(70), ContextUsageTone.warning);
      expect(contextUsageTone(89), ContextUsageTone.warning);
    });

    test('uses danger from 90 percent', () {
      expect(contextUsageTone(89.9), ContextUsageTone.warning);
      expect(contextUsageTone(90), ContextUsageTone.danger);
      expect(contextUsageTone(100), ContextUsageTone.danger);
    });

    test('uses the compaction threshold when it is lower than 90 percent', () {
      // Default reserve 2.5 gives compaction at 97.5, so 90 still applies.
      expect(
        contextUsageTone(90, compactionReservePercent: 2.5),
        ContextUsageTone.danger,
      );
      // Reserve 15 gives compaction at 85: danger starts there.
      expect(
        contextUsageTone(84.9, compactionReservePercent: 15),
        ContextUsageTone.warning,
      );
      expect(
        contextUsageTone(85, compactionReservePercent: 15),
        ContextUsageTone.danger,
      );
      expect(
        contextUsageTone(89, compactionReservePercent: 15),
        ContextUsageTone.danger,
      );
    });

    test('never lowers danger below the compaction margin for a small reserve', () {
      // Reserve 25 gives compaction at 75, which is still above the 70 warning.
      expect(
        contextUsageTone(74.9, compactionReservePercent: 25),
        ContextUsageTone.warning,
      );
      expect(
        contextUsageTone(75, compactionReservePercent: 25),
        ContextUsageTone.danger,
      );
    });
  });
}

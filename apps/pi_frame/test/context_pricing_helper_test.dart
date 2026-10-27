import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/context_pricing_helper.dart';

void main() {
  group('ContextPricingHelper', () {
    test('identifies variable context models correctly', () {
      expect(
        hasVariableContextPricing({'id': 'anthropic/claude-3-haiku-20240307'}),
        isTrue,
      );
      expect(hasVariableContextPricing({'id': 'claude-haiku-4'}), isTrue);
      expect(hasVariableContextPricing({'name': 'Luna 1.5 Pro'}), isTrue);
      expect(hasVariableContextPricing({'id': 'gpt-4o'}), isFalse);
      expect(
        hasVariableContextPricing({
          'id': 'custom-model',
          'cost': {
            'tiers': [
              {'inputTokensAbove': 50000, 'cost': 1.0},
            ],
          },
        }),
        isTrue,
      );
    });

    test('returns correct context sizes for variable context models', () {
      final haikuSizes = getVariableContextSizes({
        'id': 'claude-3-haiku',
        'contextWindow': 200000,
      });
      expect(haikuSizes, containsAll([100000, 200000]));

      expect(getVariableContextSizes({
        'id': 'gpt-6-luna', 'contextWindow': 1000000,
      }), [272000, 1000000]);
      // Authoritative pricing metadata takes precedence over the fallback.
      expect(getVariableContextSizes({
        'id': 'gpt-6-luna', 'contextWindow': 1000000,
        'cost': {'tiers': [{'inputTokensAbove': 300000}]},
      }), [300000, 1000000]);

      final tieredSizes = getVariableContextSizes({
        'id': 'custom',
        'contextWindow': 128000,
        'cost': {
          'tiers': [
            {'inputTokensAbove': 32768},
            {'inputTokensAbove': 65536},
          ],
        },
      });
      expect(tieredSizes, containsAll([32768, 65536, 128000]));

      final cappedSizes = getVariableContextSizes({
        'id': 'custom',
        'contextWindow': 64000,
        'cost': {
          'tiers': [
            {'inputTokensAbove': 32768},
            {'inputTokensAbove': 128000},
          ],
        },
      });
      expect(cappedSizes, [32768, 64000]);
      expect(getVariableContextSizes({'id': 'claude-haiku'}), isEmpty);
    });

    test(
      'validates context maximum and calculates unused compaction margin',
      () {
        expect(isValidContextWindowLimit(200000, 200000), isTrue);
        expect(isValidContextWindowLimit(200001, 200000), isFalse);
        expect(isValidContextWindowLimit(0, 200000), isFalse);
        expect(isValidContextWindowLimit(1000, null), isFalse);
        expect(usableContextWindow(200000, 2.5), 195000);
        expect(usableContextWindow(1000000, 5), 950000);
      },
    );

    test('formats tokens and context sizes accurately', () {
      expect(formatTokens(128000), '128k');
      expect(formatTokens(1000000), '1M');
      expect(formatTokens(500), '500');

      expect(formatContextSize(32768, 200000), '32k (Tier base)');
      expect(formatContextSize(200000, 200000), '200k (Max / Tier esteso)');
      expect(formatContextSize(1048576, 2000000), '1M (Tier base)');
    });
  });
}

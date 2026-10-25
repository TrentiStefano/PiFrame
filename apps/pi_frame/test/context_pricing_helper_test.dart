import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/context_pricing_helper.dart';

void main() {
  group('ContextPricingHelper', () {
    test('identifies variable context models correctly', () {
      expect(
        hasVariableContextPricing({'id': 'anthropic/claude-3-haiku-20240307'}),
        isTrue,
      );
      expect(
        hasVariableContextPricing({'id': 'claude-haiku-4'}),
        isTrue,
      );
      expect(
        hasVariableContextPricing({'name': 'Luna 1.5 Pro'}),
        isTrue,
      );
      expect(
        hasVariableContextPricing({'id': 'gpt-4o'}),
        isFalse,
      );
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
    });

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

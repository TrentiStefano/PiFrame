/// Helper functions for models with variable context pricing (Luna, Haiku, etc.)
library;

bool hasVariableContextPricing(Map<String, dynamic> model) {
  final cost = model['cost'];
  if (cost is Map) {
    final tiers = cost['tiers'];
    if (tiers is List && tiers.isNotEmpty) {
      return true;
    }
  }

  final id = (model['id'] ?? '').toString().toLowerCase();
  final name = (model['name'] ?? '').toString().toLowerCase();

  return id.contains('luna') ||
      name.contains('luna') ||
      id.contains('haiku') ||
      name.contains('haiku');
}

List<int> getVariableContextSizes(Map<String, dynamic> model) {
  final fullWindow = (model['contextWindow'] as num?)?.toInt() ?? 1000000;
  final sizes = <int>{};

  final cost = model['cost'];
  if (cost is Map) {
    final tiers = cost['tiers'];
    if (tiers is List) {
      for (final tier in tiers) {
        if (tier is Map && tier['inputTokensAbove'] is num) {
          sizes.add((tier['inputTokensAbove'] as num).toInt());
        }
      }
    }
  }

  final id = (model['id'] ?? '').toString().toLowerCase();
  final name = (model['name'] ?? '').toString().toLowerCase();

  if (sizes.isEmpty) {
    if (id.contains('haiku') || name.contains('haiku')) {
      sizes.addAll([100000, 200000]);
    } else if (id.contains('luna') || name.contains('luna')) {
      sizes.add(200000);
    }
  }

  sizes.add(fullWindow);

  final list = sizes.toList()..sort();
  return list;
}

String formatTokens(dynamic count) {
  if (count == null) return '—';
  final numVal = count is num ? count : num.tryParse(count.toString());
  if (numVal == null) return count.toString();

  if (numVal >= 1048576 && numVal % 1048576 == 0) {
    return '${numVal ~/ 1048576}M';
  }
  if (numVal >= 1000000) {
    final m = numVal / 1000000.0;
    return m % 1 == 0 ? '${m.toInt()}M' : '${m.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}M';
  }
  if (numVal % 1000 == 0) {
    return '${numVal ~/ 1000}k';
  }
  if (numVal % 1024 == 0) {
    return '${numVal ~/ 1024}k';
  }
  if (numVal >= 1000) {
    final k = (numVal / 1000.0).round();
    return '${k}k';
  }
  return numVal.toInt().toString();
}

String formatContextSize(int size, int fullWindow) {
  final formatted = formatTokens(size);
  if (size >= fullWindow) {
    return '$formatted (Max / Tier esteso)';
  }
  return '$formatted (Tier base)';
}

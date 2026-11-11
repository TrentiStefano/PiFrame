import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/harness/harness_extensions.dart';

void main() {
  testWidgets('selector matching finds keys and visible text, skips offstage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('Visible label', key: ValueKey('label-key')),
              const TextField(
                decoration: InputDecoration(hintText: 'Search here'),
              ),
              Offstage(
                offstage: true,
                child: const Text('Hidden label', key: ValueKey('hidden-key')),
              ),
            ],
          ),
        ),
      ),
    );
    final root = WidgetsBinding.instance.rootElement!;

    expect(HarnessInspector.findMatches(root, key: 'label-key'), hasLength(1));
    expect(HarnessInspector.findMatches(root, text: 'Search here'), isNotEmpty);
    expect(HarnessInspector.findMatches(root, key: 'hidden-key'), isEmpty);
    expect(HarnessInspector.findTarget(root, key: 'label-key'), isNotNull);
  });

  testWidgets('tree serialization includes visible keyed text with bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Tree label', key: ValueKey('tree-label'))),
      ),
    );
    final root = WidgetsBinding.instance.rootElement!;

    final entries = HarnessInspector.serializeTree(root);
    final entry = entries.firstWhere((item) => item['key'] == 'tree-label');
    expect(entry['type'], 'Text');
    expect(entry['text'], 'Tree label');
    expect(entry['rect'], isA<List<double>>());
    expect(HarnessInspector.serializeTree(root, filter: 'missing'), isEmpty);
  });
}

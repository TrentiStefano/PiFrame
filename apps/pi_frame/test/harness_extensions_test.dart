import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/harness_mode.dart';
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

  testWidgets('tree includes visible list-row text and IconButton tooltips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                title: const Text('notes.md'),
                trailing: IconButton(
                  tooltip: 'Open notes.md',
                  onPressed: () {},
                  icon: const Icon(Icons.open_in_new),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Review notes.md'),
              ),
            ],
          ),
        ),
      ),
    );
    final root = WidgetsBinding.instance.rootElement!;
    final entries = HarnessInspector.serializeTree(root, filter: 'notes.md');

    expect(entries.any((entry) => entry['text'] == 'notes.md'), isTrue);
    expect(
      entries.any(
        (entry) =>
            entry['type'] == 'IconButton' && entry['text'] == 'Open notes.md',
      ),
      isTrue,
    );
    expect(
      entries.any(
        (entry) =>
            entry['type'] == 'TextButton' && entry['text'] == 'Review notes.md',
      ),
      isTrue,
    );
    expect(entries.every((entry) => entry['covered'] is bool), isTrue);
    expect(
      HarnessInspector.findMatches(root, text: 'Open notes.md'),
      isNotEmpty,
    );
    expect(
      HarnessInspector.serializeTreeResult(root, maxEntries: 1)['truncated'],
      isTrue,
    );
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

  test('media overrides affect only harness-mode media data', () {
    const base = MediaQueryData(
      textScaler: TextScaler.linear(1),
      platformBrightness: Brightness.light,
    );
    const overrides = HarnessMediaOverrides(
      textScale: 1.4,
      reduceMotion: true,
      brightness: Brightness.dark,
    );

    final normal = applyHarnessMediaOverrides(
      base,
      harnessEnabled: false,
      reduceMotionPreference: false,
      overrides: overrides,
    );
    expect(normal.textScaler.scale(1), 1);
    expect(normal.disableAnimations, isFalse);
    expect(normal.platformBrightness, Brightness.light);

    final harness = applyHarnessMediaOverrides(
      base,
      harnessEnabled: true,
      reduceMotionPreference: false,
      overrides: overrides,
    );
    expect(harness.textScaler.scale(1), 1.4);
    expect(harness.disableAnimations, isTrue);
    expect(harness.platformBrightness, Brightness.dark);

    final appPreference = applyHarnessMediaOverrides(
      base,
      harnessEnabled: false,
      reduceMotionPreference: true,
    );
    expect(appPreference.disableAnimations, isTrue);
  });

  testWidgets('pointer dispatch supports tapAt, rightClick, and drag', (
    tester,
  ) async {
    var taps = 0;
    var secondaryTaps = 0;
    var dragUpdates = 0;
    Widget target(
      String key, {
      VoidCallback? onTap,
      GestureTapCallback? onSecondaryTap,
      GestureDragUpdateCallback? onPanUpdate,
    }) => GestureDetector(
      key: ValueKey(key),
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      onPanUpdate: onPanUpdate,
      child: Container(width: 180, height: 72, color: Colors.blue),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                target('tap-target', onTap: () => taps++),
                target('right-target', onSecondaryTap: () => secondaryTaps++),
                target('drag-target', onPanUpdate: (_) => dragUpdates++),
              ],
            ),
          ),
        ),
      ),
    );

    await HarnessInspector.dispatchPointer(
      tester.getCenter(find.byKey(const ValueKey('tap-target'))),
      kind: HarnessPointerAction.tapAt,
    );
    await tester.pump();
    expect(taps, 1);

    await HarnessInspector.dispatchPointer(
      tester.getCenter(find.byKey(const ValueKey('right-target'))),
      kind: HarnessPointerAction.rightClick,
    );
    await tester.pump();
    expect(secondaryTaps, 1);

    await HarnessInspector.dispatchPointer(
      tester.getCenter(find.byKey(const ValueKey('drag-target'))),
      kind: HarnessPointerAction.drag,
      delta: const Offset(80, 0),
    );
    await tester.pump();
    expect(dragUpdates, greaterThan(0));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/main.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';

void main() {
  testWidgets('PiFrameApp loads smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(ProviderScope(
      overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
      child: const PiFrameApp(),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify app starts and renders
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/main.dart';

void main() {
  testWidgets('PiCrustApp loads smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: PiCrustApp()));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify app starts and renders
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

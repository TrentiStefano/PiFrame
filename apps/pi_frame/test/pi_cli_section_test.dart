import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/settings/pi_cli_section.dart';

void main() {
  testWidgets('PiCliSection renders all pi command buttons and custom input', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const tokens = FrameTokens.dark;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PiCliSection(tokens: tokens)),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Pi CLI Interface'), findsOneWidget);

    // Verify Key Command Buttons
    expect(find.text('Update Pi CLI'), findsOneWidget);
    expect(find.text('pi update'), findsOneWidget);

    expect(find.text('Update Extensions'), findsOneWidget);
    expect(find.text('pi update --extensions'), findsOneWidget);

    expect(find.text('Update Model Catalog'), findsOneWidget);
    expect(find.text('pi update --models'), findsOneWidget);

    expect(find.text('Update All'), findsOneWidget);
    expect(find.text('pi update --all'), findsOneWidget);

    expect(find.text('List Extensions'), findsOneWidget);
    expect(find.text('MCP Server Status'), findsOneWidget);
    expect(find.text('Pi CLI Version'), findsOneWidget);

    // Verify Custom Command Input
    expect(find.text('Custom command'), findsOneWidget);
    expect(find.text('pi '), findsOneWidget);
    expect(find.text('Run'), findsWidgets);

    // Verify Output Console
    expect(find.text('Output'), findsOneWidget);
  });
}

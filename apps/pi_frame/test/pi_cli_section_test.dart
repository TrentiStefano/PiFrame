import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/platform/host_environment_service.dart';
import 'package:pi_frame/data/platform/process_service.dart';
import 'package:pi_frame/features/settings/pi_cli_section.dart';

import 'support/fake_platform_services.dart';

void main() {
  Future<FakeProcessService> pumpSection(WidgetTester tester, {bool isWindows = false}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const tokens = FrameTokens.dark;
    final processes = FakeProcessService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          processServiceProvider.overrideWithValue(processes),
          hostEnvironmentServiceProvider.overrideWithValue(FakeHostEnvironmentService(isWindows: isWindows)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PiCliSection(tokens: tokens)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return processes;
  }

  testWidgets('a command streams its output into the console and reports its exit code', (tester) async {
    final processes = await pumpSection(tester);

    await tester.tap(find.byKey(const ValueKey('pi-cli-run-pi---version')));
    await tester.pump();

    expect(processes.started, hasLength(1));
    expect(processes.started.single.startArguments, contains('--version'));

    processes.started.single.writeStdout('pi 0.9.1-marker\n');
    await tester.pump();
    expect(find.textContaining('pi 0.9.1-marker'), findsOneWidget);

    await processes.started.single.exit(0);
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('Stop kills the running command', (tester) async {
    final processes = await pumpSection(tester);

    await tester.tap(find.byKey(const ValueKey('pi-cli-run-pi---version')));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(processes.started.single.killed, isTrue);
  });

  testWidgets('PiCliSection renders all pi command buttons and custom input', (tester) async {
    await pumpSection(tester);

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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/pi_install/pi_install_service.dart';
import 'package:pi_frame/features/dialogs/pi_install_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class FakePiInstallService implements PiInstallService {
  bool firstRun = true;
  bool piInstalled = false;
  bool markCompletedCalled = false;
  bool shouldSucceed = true;
  StreamController<String>? streamController;

  @override
  Future<bool> isFirstRun() async => firstRun;

  @override
  Future<void> markFirstRunCompleted() async {
    markCompletedCalled = true;
    firstRun = false;
  }

  @override
  Future<bool> isPiInstalled() async => piInstalled;

  @override
  Stream<String> installPiAgent() {
    final controller = StreamController<String>();
    streamController = controller;
    scheduleMicrotask(() async {
      controller.add('npm install -g @earendil-works/pi-coding-agent\n');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (shouldSucceed) {
        piInstalled = true;
        controller.add('[SUCCESSO] @earendil-works/pi-coding-agent installato con successo!\n');
      } else {
        controller.add('[ERRORE] Errore durante l\'installazione npm\n');
      }
      await controller.close();
    });
    return controller.stream;
  }
}

void main() {
  Widget buildTestableWidget({
    required PiInstallService service,
  }) {
    return ProviderScope(
      overrides: [
        piInstallServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [FrameTokens.dark],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => PiInstallDialog.show(context, customService: service),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('PiInstallDialog displays initial prompt and actions', (tester) async {
    final fakeService = FakePiInstallService();
    await tester.pumpWidget(buildTestableWidget(service: fakeService));

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Installazione Pi Coding Agent'), findsOneWidget);
    expect(find.text('Pi Coding Agent non rilevato'), findsOneWidget);
    expect(find.byKey(const ValueKey('pi-install-later-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('pi-install-now-btn')), findsOneWidget);
  });

  testWidgets('PiInstallDialog later button dismisses and marks completed', (tester) async {
    final fakeService = FakePiInstallService();
    await tester.pumpWidget(buildTestableWidget(service: fakeService));

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Click "Più tardi"
    await tester.tap(find.byKey(const ValueKey('pi-install-later-btn')));
    await tester.pumpAndSettle();

    expect(find.text('Installazione Pi Coding Agent'), findsNothing);
    expect(fakeService.markCompletedCalled, isTrue);
  });

  testWidgets('PiInstallDialog runs install and displays success state', (tester) async {
    final fakeService = FakePiInstallService();
    await tester.pumpWidget(buildTestableWidget(service: fakeService));

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Click "Installa adesso"
    await tester.tap(find.byKey(const ValueKey('pi-install-now-btn')));
    await tester.pump(); // Start installation
    await tester.pumpAndSettle(); // Wait for stream to finish

    expect(find.text('Installazione completata con successo!'), findsOneWidget);
    expect(find.byKey(const ValueKey('pi-install-done-btn')), findsOneWidget);
    expect(fakeService.markCompletedCalled, isTrue);
    expect(fakeService.piInstalled, isTrue);

    // Click done button
    await tester.tap(find.byKey(const ValueKey('pi-install-done-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Installazione completata con successo!'), findsNothing);
  });

  testWidgets('PiInstallDialog handles install failure with retry option', (tester) async {
    final fakeService = FakePiInstallService()..shouldSucceed = false;
    await tester.pumpWidget(buildTestableWidget(service: fakeService));

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Click "Installa adesso"
    await tester.tap(find.byKey(const ValueKey('pi-install-now-btn')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Installazione non riuscita. Verifica i log sottostanti.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pi-install-retry-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('pi-install-done-btn')), findsOneWidget);
  });
}

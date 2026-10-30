import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _SlowPickerSession extends SessionStateNotifier {
  _SlowPickerSession() : super('slow-picker', null) {
    state = const SessionState(
      sessionId: 'slow-picker',
      cwd: '/fixture',
      currentModel: 'Model A',
    );
  }

  /// When set, every model catalogue request waits for it (simulates a slow daemon).
  Completer<void>? gate;
  int modelLoads = 0;
  final selected = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getAvailableModels() async {
    modelLoads++;
    await gate?.future;
    return [
      {
        'provider': 'fixture',
        'id': 'a',
        'name': 'Model A',
        'contextWindow': 1000,
      },
      {
        'provider': 'fixture',
        'id': 'b',
        'name': 'Model B',
        'contextWindow': 1000,
      },
    ];
  }

  @override
  Future<void> setModel(String provider, String modelId) async {
    selected.add('$provider/$modelId');
  }

  @override
  Future<List<Map<String, dynamic>>> getCommands() async => [];
}

void main() {
  Future<void> mount(WidgetTester tester, _SlowPickerSession session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('slow-picker').overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Composer(sessionId: 'slow-picker'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final chip = find.byKey(const ValueKey('composer-model-picker-btn'));

  testWidgets('repeated taps while the model list loads open a single menu', (
    tester,
  ) async {
    final session = _SlowPickerSession();
    await mount(tester, session);
    final loadsAfterMount = session.modelLoads;

    session.gate = Completer<void>();
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    // Only the first tap started a catalogue request.
    expect(session.modelLoads, loadsAfterMount + 1);

    session.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<Map<String, dynamic>>), findsNWidgets(2));

    await tester.tap(find.text('Model B'));
    await tester.pumpAndSettle();
    expect(session.selected, ['fixture/b']);
    expect(find.byType(PopupMenuItem<Map<String, dynamic>>), findsNothing);
  });

  testWidgets('the model menu can be opened again after it was closed', (
    tester,
  ) async {
    final session = _SlowPickerSession();
    await mount(tester, session);

    for (var round = 0; round < 2; round++) {
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.byType(PopupMenuItem<Map<String, dynamic>>),
        findsNWidgets(2),
      );
      // Dismiss through the barrier without choosing.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<Map<String, dynamic>>), findsNothing);
    }
    expect(session.selected, isEmpty);
  });
}

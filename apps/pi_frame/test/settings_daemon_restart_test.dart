import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/features/settings/sections/daemon_section.dart';

/// Daemon tab restart flow (task 8.3): the consequence text is always shown,
/// and restarting while a run is active asks for confirmation first.
void main() {
  Future<int> pumpDaemon(WidgetTester tester, {required bool runActive}) async {
    var restarts = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(
            body: DaemonSection(
              tokens: FrameTokens.dark,
              strings: const AppStrings(AppLanguage.it),
              endpoint: null,
              isLoadingConfig: false,
              workerIdleTimeoutMinutes: 30,
              configStatusMessage: null,
              isRestartingDaemon: false,
              onRestartDaemon: () => restarts++,
              onUpdateTimeout: (_) {},
              runActive: runActive,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return restarts;
  }

  testWidgets('restart explains the consequence under the button', (tester) async {
    await pumpDaemon(tester, runActive: false);

    expect(find.text('Le sessioni in corso verranno riconnesse.'), findsOneWidget);
  });

  testWidgets('restart runs directly when no run is active', (tester) async {
    await pumpDaemon(tester, runActive: false);

    await tester.tap(find.byKey(const ValueKey('settings-restart-daemon-btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-daemon-restart-confirm-btn')), findsNothing);
  });

  testWidgets('restart asks first while a run is active and can be cancelled', (tester) async {
    final restarts = await pumpDaemon(tester, runActive: true);

    await tester.tap(find.byKey(const ValueKey('settings-restart-daemon-btn')));
    await tester.pumpAndSettle();

    expect(find.text('Riavviare il daemon?'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(restarts, 0);
  });

  testWidgets('confirming the restart while a run is active restarts the daemon', (tester) async {
    var restarts = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
          home: Scaffold(
            body: DaemonSection(
              tokens: FrameTokens.dark,
              strings: const AppStrings(AppLanguage.it),
              endpoint: null,
              isLoadingConfig: false,
              workerIdleTimeoutMinutes: 30,
              configStatusMessage: null,
              isRestartingDaemon: false,
              onRestartDaemon: () => restarts++,
              onUpdateTimeout: (_) {},
              runActive: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-restart-daemon-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-daemon-restart-confirm-btn')));
    await tester.pumpAndSettle();

    expect(restarts, 1);
  });
}

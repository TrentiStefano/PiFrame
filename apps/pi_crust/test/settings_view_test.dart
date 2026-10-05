import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/features/settings/settings_view.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';

void main() {
  testWidgets('SettingsView renders all 4 tabs properly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
          home: Scaffold(body: SettingsView(onClose: () {})),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    // Verify all 4 tabs exist
    expect(find.text('PI CLI'), findsOneWidget);
    expect(find.text('DAEMON'), findsOneWidget);
    expect(find.text('ASPETTO'), findsOneWidget);
    expect(find.text('PRIVACY'), findsOneWidget);
  });

  testWidgets(
    'SettingsView enforces D16 Zero Remote Telemetry in Privacy tab',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [daemonEndpointProvider.overrideWith((ref) async => null)],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [CrustTokens.dark]),
            home: Scaffold(
              body: SettingsView(onClose: () {}, initialTabIndex: 3),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));

      // Verify normative D16 disclosure text is present
      expect(
        find.textContaining(
          'Pi-Crust non invia alcun dato di utilizzo a server remoti.',
        ),
        findsOneWidget,
      );

      // NEGATIVE ASSERTION FOR D16: Zero Remote Telemetry
      // Ensure there are NO Switch, Checkbox, or Radio controls anywhere in the settings/privacy page!
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Radio), findsNothing);
      expect(find.textContaining('Invia statistiche'), findsNothing);
      expect(find.textContaining('Abilita telemetria'), findsNothing);
      expect(find.textContaining('Abilita analytics'), findsNothing);
    },
  );
}

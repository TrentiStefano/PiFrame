import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_settings.dart';
import 'package:pi_frame/features/settings/diagnostics.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _strings = AppStrings(AppLanguage.en);

Widget _diagnostics({
  required DaemonConnectionState connection,
  required List<Map<String, dynamic>> sessions,
  String? fixtureLabel,
}) {
  return ProviderScope(
    overrides: [
      connectionStateProvider.overrideWith((ref) => Stream.value(connection)),
      sessionListProvider.overrideWith((ref) async => sessions),
      diagnosticsFixtureLabelProvider.overrideWithValue(fixtureLabel),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
      home: const Scaffold(body: DiagnosticsSection()),
    ),
  );
}

void main() {
  testWidgets('shows the daemon connection state from the connection provider', (tester) async {
    await tester.pumpWidget(_diagnostics(connection: DaemonConnectionState.connected, sessions: const []));
    await tester.pumpAndSettle();

    expect(find.text(_strings.diagTitle), findsOneWidget);
    expect(find.text(_strings.daemonConnectionStateLabel(DaemonConnectionState.connected.name)), findsOneWidget);
  });

  testWidgets('shows the disconnected state when the daemon is down', (tester) async {
    await tester.pumpWidget(_diagnostics(connection: DaemonConnectionState.disconnected, sessions: const []));
    await tester.pumpAndSettle();

    expect(find.text(_strings.daemonConnectionStateLabel(DaemonConnectionState.disconnected.name)), findsOneWidget);
  });

  testWidgets('a fixture label is shown as a warning tag only when one is set', (tester) async {
    await tester.pumpWidget(
      _diagnostics(connection: DaemonConnectionState.connected, sessions: const [], fixtureLabel: 'Fixture data'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('diagnostics-fixture-label')), findsOneWidget);
    expect(find.text('Fixture data'), findsOneWidget);
  });

  testWidgets('no fixture label tag appears outside a fixture build', (tester) async {
    await tester.pumpWidget(_diagnostics(connection: DaemonConnectionState.connected, sessions: const []));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('diagnostics-fixture-label')), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_shell.dart';
import 'package:pi_frame/features/sessions_sidebar/pinned_sessions_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _PinnedNotifier extends PinnedSessionsNotifier {
  // In memory only, so the test never rewrites the user's real pins file.
  _PinnedNotifier() : super(const []);
}

class _IdleClient extends PcpClient {
  _IdleClient() : super(port: 1, token: 'test');

  @override
  Stream<PcpEvent> events(String sessionId) => const Stream.empty();

  @override
  Stream<PcpSnapshot> snapshots(String sessionId) => const Stream.empty();
}

Future<void> _pump(WidgetTester tester, {required List<Map<String, dynamic>> sessions, PcpClient? client}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pcpClientProvider.overrideWithValue(client),
        pinnedSessionsProvider.overrideWith((ref) => _PinnedNotifier()),
        sessionListProvider.overrideWith((ref) async => sessions),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: SessionsSidebar()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search with no match offers one action that clears the search', (tester) async {
    await _pump(
      tester,
      client: _IdleClient(),
      sessions: [
        {'id': 'one', 'name': 'PiFrame', 'cwd': r'C:\repo\PiFrame'},
      ],
    );
    final strings = AppStrings(AppLanguage.en);

    await tester.enterText(find.byType(TextField), 'nomatch');
    await tester.pumpAndSettle();

    expect(find.text(strings.noSessionsMatchFilters), findsOneWidget);
    expect(find.byKey(const ValueKey('sessions-empty-clear-search')), findsOneWidget);
    expect(find.text(strings.clearSearchAction), findsOneWidget);
    expect(find.byKey(const ValueKey('sessions-empty-new-session')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sessions-empty-clear-search')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.byKey(const ValueKey('session-row-one')), findsOneWidget);
    expect(find.byKey(const ValueKey('sessions-empty-clear-search')), findsNothing);
  });

  testWidgets('no sessions at all offers one action that starts a new session', (tester) async {
    await _pump(tester, client: _IdleClient(), sessions: const []);
    final strings = AppStrings(AppLanguage.en);

    expect(find.text(strings.noSessionsFound), findsOneWidget);
    expect(find.byKey(const ValueKey('sessions-empty-clear-search')), findsNothing);
    final action = find.byKey(const ValueKey('sessions-empty-new-session'));
    expect(action, findsOneWidget);
    expect(find.text(strings.newSessionAction), findsWidgets);
    expect(tester.widget<TextButton>(action).onPressed, isNotNull);
  });

  testWidgets('no sessions at all with the daemon offline disables the new-session action', (tester) async {
    await _pump(tester, client: null, sessions: const []);

    final action = find.byKey(const ValueKey('sessions-empty-new-session'));
    expect(action, findsOneWidget);
    expect(tester.widget<TextButton>(action).onPressed, isNull);
  });
}

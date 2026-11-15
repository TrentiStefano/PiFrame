import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_shell.dart';
import 'package:pi_frame/features/sessions_sidebar/session_actions.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Answers `session.create` with a reply that carries no session id.
class _NoIdClient extends PcpClient {
  _NoIdClient() : super(port: 1, token: 'test');

  int creates = 0;

  @override
  Stream<PcpEvent> events(String sessionId) => const Stream.empty();

  @override
  Stream<PcpSnapshot> snapshots(String sessionId) => const Stream.empty();

  @override
  Future<Map<String, dynamic>> sendCommand(PcpCommand command) async {
    if (command.type == 'session.create') creates++;
    return {'status': 'ok', 'data': <String, dynamic>{}};
  }
}

class _CreateButton extends ConsumerWidget {
  const _CreateButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ElevatedButton(
        key: const ValueKey('create-probe'),
        onPressed: () => createSession(context, ref, cwd: '/work/alpha'),
        child: const Text('create'),
      ),
    );
  }
}

void main() {
  testWidgets('session create without a session id shows an error snackbar', (
    tester,
  ) async {
    final client = _NoIdClient();
    final container = ProviderContainer(
      overrides: [pcpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final expected = container.read(appStringsProvider).sessionCreateNoIdNotice;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(body: _CreateButton()),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('create-probe')));
    await tester.pumpAndSettle();

    expect(client.creates, 1);
    expect(find.text(expected), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The UI stays usable: a second attempt reaches the daemon again.
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('create-probe')));
    await tester.pumpAndSettle();
    expect(client.creates, 2);
    expect(tester.takeException(), isNull);
  });
}

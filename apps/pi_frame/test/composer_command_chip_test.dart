import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/composer/composer_settings.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _FakeSession extends SessionStateNotifier {
  final sentPrompts = <String>[];
  final commands = <String>[];

  _FakeSession() : super('s1', null) {
    state = const SessionState(
      sessionId: 's1',
      cwd: '/repo',
      agentStatus: AgentStatus.idle,
      entries: [],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCommands() async => [
    {
      'name': 'reload',
      'description': 'Reload Pi resources',
      'source': 'builtin',
    },
    {
      'name': 'caveman',
      'description': 'Terse mode',
      'argumentHint': '[level]',
      'source': 'extension',
    },
    {
      'name': 'review',
      'description': 'Code review template',
      'source': 'prompt',
    },
  ];

  @override
  Future<void> runCommand(String command) async => commands.add(command);

  @override
  Future<void> sendPrompt(String text, {String? streamingBehavior}) async =>
      sentPrompts.add(text);
}

Future<_FakeSession> _pump(WidgetTester tester) async {
  final session = _FakeSession();
  final settings = ComposerSettingsNotifier()..setSendWithEnter(true);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        activeSessionIdProvider.overrideWith((ref) => 's1'),
        sessionStateFamily('s1').overrideWith((ref) => session),
        composerSettingsProvider.overrideWith((ref) => settings),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: Composer(sessionId: 's1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(TextField));
  return session;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

final _chip = find.byKey(const ValueKey('composer-command-chip'));

void main() {
  testWidgets(
    'menu selection stages /reload as a chip, Enter runs it without a chat message',
    (tester) async {
      final session = await _pump(tester);
      await tester.enterText(find.byType(TextField), '/rel');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_chip, findsOneWidget);
      expect(find.text('/reload'), findsOneWidget);
      expect(_fieldText(tester), isEmpty);
      expect(session.commands, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.commands, ['/reload']);
      expect(session.sentPrompts, isEmpty);
      expect(_chip, findsNothing);
    },
  );

  testWidgets(
    'arrow keys pick the command and typed arguments stay separate from it',
    (tester) async {
      final session = await _pump(tester);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(
        LogicalKeyboardKey.arrowDown,
      ); // reload -> caveman
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('/caveman'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'full');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(session.commands, ['/caveman full']);
    },
  );

  testWidgets(
    'typing a known command and a space promotes it; Backspace returns it to text',
    (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '/reload ');
      await tester.pumpAndSettle();
      expect(_chip, findsOneWidget);
      expect(_fieldText(tester), isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(_chip, findsNothing);
      expect(_fieldText(tester), '/reload');
    },
  );

  testWidgets(
    'a command typed and sent directly becomes a chip instead of leaving as text',
    (tester) async {
      final session = await _pump(tester);
      await tester.enterText(find.byType(TextField), '/reload');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(
        LogicalKeyboardKey.escape,
      ); // close the menu, then send
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_chip, findsOneWidget);
      expect(session.sentPrompts, isEmpty);
      expect(session.commands, isEmpty);
    },
  );

  testWidgets('plain text mentioning a command is sent as a message', (
    tester,
  ) async {
    final session = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'why does /reload fail?');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(session.sentPrompts, ['why does /reload fail?']);
    expect(session.commands, isEmpty);
    expect(_chip, findsNothing);
  });

  testWidgets('prompt templates still go out as a user message', (
    tester,
  ) async {
    final session = await _pump(tester);
    await tester.enterText(find.byType(TextField), '/review ');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(session.sentPrompts, ['/review']);
    expect(session.commands, isEmpty);
  });
}

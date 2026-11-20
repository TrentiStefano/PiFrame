import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _TreeFakeClient extends PcpClient {
  _TreeFakeClient() : super(port: 1, token: 'test');

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': '/repo',
      'files': [
        {'path': 'src/app.dart', 'sizeBytes': 10},
      ],
      'truncated': false,
    },
  };
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pcpClientProvider.overrideWithValue(_TreeFakeClient()),
        sessionStateFamily('session-a').overrideWith(
          (ref) => SessionStateNotifier('session-a', null)
            ..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [FrameTokens.light]),
        home: const Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: RepositoryPane(sessionId: 'session-a'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('folder context menu offers new session, add folder to chat and copy path', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('src'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tree-menu-session')), findsOneWidget);
    expect(find.text('Nuova sessione qui'), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-menu-copy')), findsOneWidget);
    // Folders get the folder variant of add-to-chat, never the file one.
    expect(find.byKey(const ValueKey('tree-menu-chat-folder')), findsOneWidget);
    expect(find.text('Aggiungi cartella alla chat'), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-menu-chat')), findsNothing);
  });

  testWidgets('Shift+F10 on a focused tree row opens that row menu', (
    tester,
  ) async {
    await _pump(tester);
    // Focus the folder row's own focus node, then press Shift+F10 instead of
    // right-clicking. The folder menu offers the folder actions.
    final observer = Focus.of(tester.element(find.text('src')));
    (observer.canRequestFocus
            ? observer
            : observer.descendants.firstWhere((n) => n.canRequestFocus))
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tree-menu-session')), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-menu-copy')), findsOneWidget);
  });

  testWidgets('add-to-chat on a file row is revealed on hover', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('tree-add-to-chat-src/app.dart'));
    expect(action, findsOneWidget);
    Opacity opacity() => tester.widget<Opacity>(
      find.ancestor(of: action, matching: find.byType(Opacity)).first,
    );
    expect(opacity().opacity, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('app.dart')));
    await tester.pumpAndSettle();
    expect(opacity().opacity, 1);
    expect(tester.widget<FrameIconAction>(action).tooltip, 'Aggiungi alla chat');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/workspace/editor/code_line_layout.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/frame_icon_action.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _fileContent = 'alpha\nbeta\ngamma\ndelta\n';

/// One file at the repository root, five logical lines (the last one empty).
class _EditorFakeClient extends PcpClient {
  _EditorFakeClient() : super(port: 1, token: 'test');

  String diskContent = _fileContent;
  String diskRevision = 'revision-1';
  int saveCount = 0;

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async => {
    'data': {
      'rootPath': '/repo',
      'files': [
        {'path': 'main.dart', 'sizeBytes': diskContent.length},
        {'path': 'README.md', 'sizeBytes': 20},
      ],
      'truncated': false,
    },
  };

  @override
  Future<Map<String, dynamic>> readWorkspaceFile(
    String sessionId,
    String path,
  ) async => {
    'data': {
      'rootPath': '/repo',
      'path': path,
      'content': path == 'README.md' ? '# Title\nBody text.' : diskContent,
      'revision': diskRevision,
      'sizeBytes': diskContent.length,
    },
  };

  @override
  Future<Map<String, dynamic>> saveWorkspaceFile(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    saveCount++;
    diskContent = payload['content'] as String;
    diskRevision = 'revision-$saveCount';
    return {
      'data': {'path': payload['path'], 'revision': diskRevision},
    };
  }
}

Future<_EditorFakeClient> _pumpPane(WidgetTester tester) async {
  final client = _EditorFakeClient();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pcpClientProvider.overrideWithValue(client),
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
  return client;
}

Future<void> _openMainDart(WidgetTester tester) async {
  await tester.tap(find.text('main.dart'));
  await tester.pumpAndSettle();
}

Finder get _editorField => find.byKey(const ValueKey('repository-editor-session-a'));

TextEditingController _editorController(WidgetTester tester) =>
    tester.widget<TextField>(_editorField).controller!;

Future<void> _pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gutter has one number per logical line and a 44 px width', (
    tester,
  ) async {
    await _pumpPane(tester);
    await _openMainDart(tester);

    final gutter = find.byKey(const ValueKey('repository-editor-gutter'));
    expect(gutter, findsOneWidget);
    final painter =
        tester.widget<CustomPaint>(gutter).painter! as CodeLineGutterPainter;
    expect(painter.lineCount, _fileContent.split('\n').length);
    expect(tester.getSize(gutter).width, 44);
    expect(painter.heights.length, painter.lineCount);
  });

  testWidgets('markdown wraps by default, code does not, toggle is kept', (
    tester,
  ) async {
    await _pumpPane(tester);
    await _openMainDart(tester);
    final wrapToggle = find.byKey(const ValueKey('repository-editor-wrap-btn'));
    expect(tester.widget<FrameIconAction>(wrapToggle).selected, isFalse);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    // Markdown opens in preview; switch to the source to reach the editor.
    await tester.tap(find.byKey(const ValueKey('repository-markdown-toggle-btn')));
    await tester.pumpAndSettle();
    expect(tester.widget<FrameIconAction>(wrapToggle).selected, isTrue);

    await tester.tap(wrapToggle);
    await tester.pumpAndSettle();
    expect(tester.widget<FrameIconAction>(wrapToggle).selected, isFalse);
  });

  testWidgets('add to chat from a selection passes the real line range', (
    tester,
  ) async {
    final client = await _pumpPane(tester);
    await _openMainDart(tester);
    expect(client.saveCount, 0);

    // Select "beta\ngamma": lines 2 to 3.
    final editor = _editorController(tester);
    editor.selection = const TextSelection(baseOffset: 6, extentOffset: 16);
    await tester.pump();

    final editableFinder = find.descendant(
      of: _editorField,
      matching: find.byType(EditableText),
    );
    final editorState = tester.state<EditableTextState>(editableFinder);
    final menu =
        tester.widget<TextField>(_editorField).contextMenuBuilder!(
              tester.element(_editorField),
              editorState,
            )
            as AdaptiveTextSelectionToolbar;
    menu.buttonItems!
        .singleWhere(
          (item) => item.label == 'Aggiungi alla chat (main.dart:L2–L3)',
        )
        .onPressed!
        .call();

    final draft = ProviderScope.containerOf(
      tester.element(find.byType(RepositoryPane)),
    ).read(composerDraftProvider('session-a'));
    expect(draft, contains('main.dart:2-3'));
    expect(draft, contains('beta\ngamma'));
  });

  testWidgets('dirty file shows the dot and a filled Salva; Ctrl+S saves it', (
    tester,
  ) async {
    final client = await _pumpPane(tester);
    await _openMainDart(tester);

    Finder saveButton() => find.byKey(const ValueKey('repository-save-btn'));
    // The dot is its own widget (outside the ellipsized path) so a long
    // file name can never hide the unsaved state.
    Finder dirtyDot() => find.byKey(const ValueKey('repository-editor-dirty-mark'));
    // Clean: text button, no dot.
    expect(tester.widget(saveButton()), isA<TextButton>());
    expect(dirtyDot(), findsNothing);

    await tester.tap(_editorField);
    await tester.pumpAndSettle();
    await tester.enterText(_editorField, 'alpha\nbeta\nedited\n');
    await tester.pumpAndSettle();
    expect(tester.widget(saveButton()), isA<FilledButton>());
    expect(dirtyDot(), findsOneWidget);

    await _pressCtrl(tester, LogicalKeyboardKey.keyS);
    expect(client.saveCount, 1);
    expect(client.diskContent, 'alpha\nbeta\nedited\n');
    expect(tester.widget(saveButton()), isA<TextButton>());
    expect(dirtyDot(), findsNothing);
  });

  testWidgets('Ctrl+G moves the caret to the requested line', (tester) async {
    await _pumpPane(tester);
    await _openMainDart(tester);
    await tester.tap(_editorField);
    await tester.pumpAndSettle();

    await _pressCtrl(tester, LogicalKeyboardKey.keyG);
    expect(find.text('Vai alla riga'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('repository-goto-line-field')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey('repository-goto-line-confirm')));
    await tester.pumpAndSettle();

    // Line 3 starts after "alpha\n" and "beta\n".
    expect(_editorController(tester).selection.baseOffset, 11);
  });

  testWidgets('closing a dirty file asks Salva / Non salvare / Annulla', (
    tester,
  ) async {
    final client = await _pumpPane(tester);
    await _openMainDart(tester);
    await tester.tap(_editorField);
    await tester.pumpAndSettle();
    await tester.enterText(_editorField, 'changed\n');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Chiudi file'));
    await tester.pumpAndSettle();
    expect(find.text('Modifiche non salvate'), findsOneWidget);
    expect(find.text('Non salvare'), findsOneWidget);
    expect(find.text('Salva'), findsWidgets);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(_editorField, findsOneWidget);
    expect(client.saveCount, 0);
  });
}

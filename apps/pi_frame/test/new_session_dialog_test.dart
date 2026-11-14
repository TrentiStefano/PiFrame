import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/dialogs/new_session_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _fieldKey = ValueKey('new-session-cwd');
const _createKey = ValueKey('new-session-create');

/// Opens the dialog from a button and records its result in [results].
Future<void> _openDialog(
  WidgetTester tester, {
  required List<String?> results,
  List<Map<String, dynamic>> sessions = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionListProvider.overrideWith((ref) async => sessions),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-dialog'),
                onPressed: () async {
                  results.add(await showNewSessionDialog(context));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-dialog')));
  await tester.pumpAndSettle();
}

/// Types [path] and waits past the 300 ms folder check.
Future<void> _type(WidgetTester tester, String path) async {
  await tester.enterText(find.byKey(_fieldKey), path);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

bool _createEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_createKey)).onPressed != null;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('piframe_dialog_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory plainFolder() => Directory('${root.path}/plain')..createSync();

  Directory gitFolder(String branch) {
    final dir = Directory('${root.path}/repo-$branch')..createSync();
    Directory('${dir.path}/.git').createSync();
    File('${dir.path}/.git/HEAD').writeAsStringSync('ref: refs/heads/$branch\n');
    return dir;
  }

  testWidgets('starts empty with Create disabled', (tester) async {
    await _openDialog(tester, results: []);

    expect(find.text('Nuova sessione'), findsWidgets);
    expect(find.byKey(_fieldKey), findsOneWidget);
    expect(_createEnabled(tester), isFalse);
  });

  testWidgets('a missing path shows Cartella non trovata and keeps Create disabled', (
    tester,
  ) async {
    await _openDialog(tester, results: []);

    await _type(tester, '${root.path}/does-not-exist');

    expect(find.text('Cartella non trovata'), findsOneWidget);
    expect(_createEnabled(tester), isFalse);
  });

  testWidgets('a Git repository shows its branch and enables Create', (tester) async {
    final repo = gitFolder('main');
    final results = <String?>[];
    await _openDialog(tester, results: results);

    await _type(tester, repo.path);

    expect(find.text('Repository Git rilevato · main'), findsOneWidget);
    expect(_createEnabled(tester), isTrue);

    await tester.tap(find.byKey(_createKey));
    await tester.pumpAndSettle();
    expect(results, [repo.path]);
  });

  testWidgets('a plain folder is valid and Enter creates it', (tester) async {
    final folder = plainFolder();
    final results = <String?>[];
    await _openDialog(tester, results: results);

    await _type(tester, folder.path);
    expect(find.text('Cartella trovata'), findsOneWidget);

    // Enter in a single-line field arrives as the text input action.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(results, [folder.path]);
  });

  testWidgets('Enter does nothing while the path is invalid', (tester) async {
    final results = <String?>[];
    await _openDialog(tester, results: results);

    await _type(tester, '${root.path}/missing');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results, isEmpty);
    expect(find.byKey(_fieldKey), findsOneWidget);
  });

  testWidgets('Escape cancels without a folder', (tester) async {
    final results = <String?>[];
    await _openDialog(tester, results: results);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(results, [null]);
  });

  testWidgets('recent folders are selectable rows that fill the field', (tester) async {
    final repo = gitFolder('dev');
    final results = <String?>[];
    await _openDialog(
      tester,
      results: results,
      sessions: [
        {'id': 's1', 'name': 'Work', 'cwd': repo.path, 'updatedAt': 10},
      ],
    );

    final row = find.byKey(ValueKey('new-session-recent-${repo.path}'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(_fieldKey)).controller!.text, repo.path);
    expect(_createEnabled(tester), isTrue);
  });
}

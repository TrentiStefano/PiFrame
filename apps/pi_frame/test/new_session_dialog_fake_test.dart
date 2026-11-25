import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/features/dialogs/new_session_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'support/fake_platform_services.dart';

const _fieldKey = ValueKey('new-session-cwd');
const _createKey = ValueKey('new-session-create');

/// Opens the dialog from a button over [files] (no real disk) and records its result in [results].
Future<void> _openDialog(
  WidgetTester tester, {
  required FileSystemService files,
  required List<String?> results,
  List<Map<String, dynamic>> sessions = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileSystemServiceProvider.overrideWithValue(files),
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

bool _createEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(_createKey)).onPressed != null;

void main() {
  testWidgets('a path missing from the file system shows Folder not found and keeps Create disabled', (tester) async {
    final files = FakeFileSystemService();
    await _openDialog(tester, files: files, results: []);

    await _type(tester, '/work/does-not-exist');

    expect(find.text('Folder not found'), findsOneWidget);
    expect(_createEnabled(tester), isFalse);
  });

  testWidgets('a Git repository in the fake file system shows its branch and enables Create', (tester) async {
    final files = FakeFileSystemService()
      ..directories.addAll({'/work/app', '/work/app/.git'})
      ..files['/work/app/.git/HEAD'] = 'ref: refs/heads/main\n';
    final results = <String?>[];
    await _openDialog(tester, files: files, results: results);

    await _type(tester, '/work/app');

    expect(find.text('Git repository detected · main'), findsOneWidget);
    expect(_createEnabled(tester), isTrue);

    await tester.tap(find.byKey(_createKey));
    await tester.pumpAndSettle();
    expect(results, ['/work/app']);
  });

  testWidgets('a plain folder is valid and Create returns it', (tester) async {
    final files = FakeFileSystemService()..directories.add('/work/notes');
    final results = <String?>[];
    await _openDialog(tester, files: files, results: results);

    await _type(tester, '/work/notes');

    expect(_createEnabled(tester), isTrue);
    await tester.tap(find.byKey(_createKey));
    await tester.pumpAndSettle();
    expect(results, ['/work/notes']);
  });

  testWidgets('recent folders from the sessions list fill the field', (tester) async {
    final files = FakeFileSystemService()..directories.add('/work/dev');
    final results = <String?>[];
    await _openDialog(
      tester,
      files: files,
      results: results,
      sessions: [
        {'id': 's1', 'name': 'Work', 'cwd': '/work/dev', 'updatedAt': 10},
      ],
    );

    await tester.tap(find.byKey(const ValueKey('new-session-recent-/work/dev')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(_fieldKey)).controller!.text, '/work/dev');
    expect(_createEnabled(tester), isTrue);
  });
}

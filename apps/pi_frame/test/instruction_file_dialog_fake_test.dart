import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/platform/file_system_service.dart';
import 'package:pi_frame/features/sessions_sidebar/instruction_file_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'support/fake_platform_services.dart';

const _folder = '/work/app';

Widget _wrap(FileSystemService files, Widget child) {
  return ProviderScope(
    overrides: [fileSystemServiceProvider.overrideWithValue(files)],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('loads an existing AGENTS.md from the file system, and saving writes it back', (tester) async {
    final files = FakeFileSystemService()..files['$_folder/AGENTS.md'] = '# Original Agent Instructions\n';

    await tester.pumpWidget(_wrap(files, const InstructionFileDialog(folder: _folder)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Repository instructions'), findsOneWidget);
    expect(find.text('Present on disk'), findsOneWidget);
    expect(find.textContaining('Original Agent Instructions'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('instruction-editor-AGENTS.md')),
      '# Updated Agent Instructions\n',
    );
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('instruction-save-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(files.files['$_folder/AGENTS.md'], contains('Updated Agent Instructions'));
    expect(find.text('Synced with disk'), findsOneWidget);
  });

  testWidgets('a folder without instruction files offers a starter template and creates the file on save', (
    tester,
  ) async {
    final files = FakeFileSystemService();

    await tester.pumpWidget(_wrap(files, const InstructionFileDialog(folder: _folder)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(files.files.containsKey('$_folder/AGENTS.md'), isFalse);
    expect(find.textContaining('Agent Instructions'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('instruction-save-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(files.files['$_folder/AGENTS.md'], startsWith('# Agent Instructions'));
  });
}

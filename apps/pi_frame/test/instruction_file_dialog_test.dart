import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/sessions_sidebar/instruction_file_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pi_frame_instructions_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget wrapWithTheme(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [FrameTokens.dark],
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  group('InstructionFileDialog tests', () {
    testWidgets('loads existing AGENTS.md, allows editing and saving', (tester) async {
      // Create existing AGENTS.md file in tempDir
      final agentsFile = File('${tempDir.path}/AGENTS.md');
      agentsFile.writeAsStringSync('# Original Agent Instructions\nAlways be helpful.');

      await tester.pumpWidget(
        wrapWithTheme(
          InstructionFileDialog(folder: tempDir.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should display dialog header and AGENTS.md chip
      expect(find.text('Istruzioni repository'), findsOneWidget);
      expect(find.byKey(const ValueKey('instruction-chip-AGENTS.md')), findsOneWidget);
      expect(find.text('Presente sul disco'), findsOneWidget);

      // Verify loaded content
      final editorFinder = find.byKey(const ValueKey('instruction-editor-AGENTS.md'));
      expect(editorFinder, findsOneWidget);
      expect(find.textContaining('Original Agent Instructions'), findsOneWidget);

      // Edit the text
      await tester.enterText(
        editorFinder,
        '# Updated Agent Instructions\nNew guidelines for pairing.',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Dirty indicator
      expect(find.text('Modifiche non salvate'), findsOneWidget);

      // Save file
      final saveBtn = find.byKey(const ValueKey('instruction-save-btn'));
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify file updated on disk
      final diskContent = agentsFile.readAsStringSync();
      expect(diskContent, contains('Updated Agent Instructions'));
      expect(diskContent, contains('New guidelines for pairing.'));
      expect(find.text('Sincronizzato con il disco'), findsOneWidget);
    });

    testWidgets('can create new instruction file like CLAUDE.md or .github/copilot-instructions.md', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          InstructionFileDialog(folder: tempDir.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Select CLAUDE.md chip
      final claudeChip = find.byKey(const ValueKey('instruction-chip-CLAUDE.md'));
      expect(claudeChip, findsOneWidget);
      await tester.tap(claudeChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('File nuovo'), findsOneWidget);

      final editorFinder = find.byKey(const ValueKey('instruction-editor-CLAUDE.md'));
      expect(editorFinder, findsOneWidget);

      await tester.enterText(editorFinder, '# Claude Guidelines\nRun pnpm test before commit.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Save
      await tester.tap(find.byKey(const ValueKey('instruction-save-btn')));
      await tester.pump();
      ScaffoldMessenger.of(
        tester.element(find.byType(InstructionFileDialog)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // Verify created on disk
      final claudeFile = File('${tempDir.path}/CLAUDE.md');
      expect(claudeFile.existsSync(), isTrue);
      expect(claudeFile.readAsStringSync(), contains('Run pnpm test before commit.'));

      // Now create nested .github/copilot-instructions.md
      final copilotChip = find.byKey(
        const ValueKey('instruction-chip-.github/copilot-instructions.md'),
      );
      expect(copilotChip, findsOneWidget);
      await tester.tap(copilotChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final copilotEditor = find.byKey(
        const ValueKey('instruction-editor-.github/copilot-instructions.md'),
      );
      await tester.enterText(copilotEditor, '# Copilot Custom Instructions');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('instruction-save-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final copilotFile = File('${tempDir.path}/.github/copilot-instructions.md');
      expect(copilotFile.existsSync(), isTrue);
      expect(copilotFile.readAsStringSync(), contains('Copilot Custom Instructions'));
    });

    testWidgets('generates instructions using Pi button and saves to disk', (tester) async {
      // Setup repo structure in tempDir
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: my_flutter_app\n');
      Directory('${tempDir.path}/lib').createSync();

      await tester.pumpWidget(
        wrapWithTheme(
          InstructionFileDialog(folder: tempDir.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final generateBtn = find.byKey(const ValueKey('instruction-generate-pi-btn'));
      expect(generateBtn, findsOneWidget);

      // Tap generate button
      await tester.tap(generateBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check that editor has received generated instruction content
      final editorFinder = find.byKey(const ValueKey('instruction-editor-AGENTS.md'));
      expect(editorFinder, findsOneWidget);
      expect(find.textContaining('Istruzioni per gli Agenti'), findsOneWidget);
      expect(find.textContaining('flutter test'), findsOneWidget);

      // Save
      final saveBtn = find.byKey(const ValueKey('instruction-save-btn'));
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify AGENTS.md saved on disk
      final agentsFile = File('${tempDir.path}/AGENTS.md');
      expect(agentsFile.existsSync(), isTrue);
      expect(agentsFile.readAsStringSync(), contains('flutter test'));
    });
  });
}


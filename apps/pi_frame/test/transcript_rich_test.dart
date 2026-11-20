import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/transcript/rich_content.dart';
import 'package:pi_frame/features/transcript/thinking_block.dart';
import 'package:pi_frame/ui/code/code_block.dart';
import 'package:pi_frame/ui/code/diff_block.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  testWidgets('ThinkingBlock collapses by default and expands on tap', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        const ThinkingBlock(
          thinkingText: 'Prima riga di sintesi\nDettaglio lungo del ragionamento interno che appare solo da espanso.',
        ),
      ),
    );

    expect(find.text('Ragionamento'), findsOneWidget);
    expect(find.textContaining('parole'), findsOneWidget);
    // Detail should not be visible when collapsed
    expect(find.text('Dettaglio lungo del ragionamento interno che appare solo da espanso.'), findsNothing);

    // Tap to expand
    await tester.tap(find.text('Ragionamento'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dettaglio lungo del ragionamento'), findsOneWidget);
  });

  testWidgets('ThinkingBlock disappears completely when thinking text is empty or whitespace even when streaming', (
    tester,
  ) async {
    await tester.pumpWidget(wrapWithTheme(const ThinkingBlock(thinkingText: '   \n  \t ', isStreaming: true)));

    expect(find.text('Ragionamento'), findsNothing);
    expect(find.byType(ThinkingBlock), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('RichContent separates text, headers, and code fences', (tester) async {
    const markdown = '''
# Titolo Principale
Ecco del testo con `inline_code`.

```dart
void main() {}
```

```diff
+nuova riga
```
''';

    await tester.pumpWidget(wrapWithTheme(const RichContent(text: markdown)));

    expect(find.text('Titolo Principale'), findsOneWidget);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.byType(DiffBlock), findsOneWidget);
  });

  test('isLikelyFilePath correctly identifies file paths', () {
    expect(isLikelyFilePath('lib/main.dart'), isTrue);
    expect(isLikelyFilePath('apps/agentd/src/workspace/gitClient.ts'), isTrue);
    expect(isLikelyFilePath('README.md'), isTrue);
    expect(isLikelyFilePath('C:\\Personale\\Repos\\project\\file.dart'), isTrue);
    expect(isLikelyFilePath('file:///c:/path/to/file.dart'), isTrue);
    expect(isLikelyFilePath('config.json'), isTrue);

    expect(isLikelyFilePath(''), isFalse);
    expect(isLikelyFilePath('hello world'), isFalse);
    expect(isLikelyFilePath('https://github.com/flutter/flutter'), isFalse);
    expect(isLikelyFilePath('git status'), isFalse);
  });

  testWidgets('RichContent marks file code mentions with file icon and CTRL+click tooltip', (tester) async {
    const textWithFile = 'Ho modificato il file `lib/main.dart` e creato `README.md`.';

    await tester.pumpWidget(wrapWithTheme(const RichContent(text: textWithFile, cwd: '/dummy/project')));

    expect(find.textContaining('lib/main.dart', findRichText: true), findsWidgets);
    expect(find.textContaining('README.md', findRichText: true), findsWidgets);
    final selectableText = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((paragraph) => paragraph.selectionRegistrar != null)
        .map((paragraph) => paragraph.text.toPlainText())
        .join();
    expect(selectableText, contains('lib/main.dart'));
    expect(selectableText, contains('README.md'));
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
    expect(find.byTooltip('CTRL+clic per aprire in esplora file'), findsWidgets);

    // Verify SelectionContainer.disabled is present so that SelectionArea does not override mouse cursor
    final disabledContainers = find.descendant(of: find.byType(RichContent), matching: find.byType(SelectionContainer));
    expect(disabledContainers, findsWidgets);

    // Verify MouseRegion with click cursor exists for file chips
    final clickMouseRegions = find.descendant(
      of: find.byType(RichContent),
      matching: find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.click),
    );
    expect(clickMouseRegions, findsWidgets);
  });

  test('resolvePathForOsExplorer correctly resolves WSL and Windows paths', () {
    // 1. WSL UNC cwd with relative path
    const wslCwd = r'\\wsl.localhost\Ubuntu\home\user\Repos\my_repo';
    final res1 = resolvePathForOsExplorer('lib/main.dart', cwd: wslCwd);
    expect(res1, r'\\wsl.localhost\Ubuntu\home\user\Repos\my_repo\lib\main.dart');

    // 2. WSL UNC cwd with Linux absolute path
    final res2 = resolvePathForOsExplorer('/home/user/Repos/my_repo/lib/main.dart', cwd: wslCwd);
    expect(res2, r'\\wsl.localhost\Ubuntu\home\user\Repos\my_repo\lib\main.dart');

    // 3. WSL file:// URI
    final res3 = resolvePathForOsExplorer('file:///home/user/Repos/my_repo/test.dart', cwd: wslCwd);
    expect(res3, r'\\wsl.localhost\Ubuntu\home\user\Repos\my_repo\test.dart');

    // 4. Already full WSL UNC path
    final res4 = resolvePathForOsExplorer(r'\\wsl$\Ubuntu\home\user\file.txt');
    expect(res4, r'\\wsl$\Ubuntu\home\user\file.txt');

    // 5. Line numbers and anchor stripped
    final res5 = resolvePathForOsExplorer('lib/main.dart:42:10#L42-L50', cwd: wslCwd);
    expect(res5, r'\\wsl.localhost\Ubuntu\home\user\Repos\my_repo\lib\main.dart');

    // 6. Linux path without a WSL distro stays a Linux path (wslpath maps it)
    expect(resolvePathForOsExplorer('lib/main.dart', cwd: '/home/user/repo'), '/home/user/repo/lib/main.dart');

    // 7. Windows cwd with relative path
    const winCwd = r'C:\Projects\my_repo';
    final res6 = resolvePathForOsExplorer('lib/main.dart', cwd: winCwd);
    expect(res6, r'C:\Projects\my_repo\lib\main.dart');
  }, skip: !Platform.isWindows);

  test('resolvePathForOsExplorer correctly resolves POSIX paths', () {
    const cwd = '/home/user/project';
    expect(resolvePathForOsExplorer('lib/main.dart', cwd: cwd), '/home/user/project/lib/main.dart');
    expect(resolvePathForOsExplorer('lib/main.dart', cwd: '$cwd/'), '/home/user/project/lib/main.dart');
    expect(resolvePathForOsExplorer('/etc/hosts', cwd: cwd), '/etc/hosts');
    expect(resolvePathForOsExplorer('file:///tmp/file.dart', cwd: cwd), '/tmp/file.dart');
    expect(resolvePathForOsExplorer('lib/main.dart:42:10#L42-L50', cwd: cwd), '/home/user/project/lib/main.dart');
    expect(resolvePathForOsExplorer('lib/main.dart'), 'lib/main.dart');
  }, skip: Platform.isWindows);

  testWidgets('RichContent renders raw file paths and markdown links with file chips', (tester) async {
    const textWithVariousLinks =
        'Vedi apps/pi_frame/lib/main.dart per i dettagli oppure consulta [la guida](docs/guide.md).';

    await tester.pumpWidget(
      wrapWithTheme(const RichContent(text: textWithVariousLinks, cwd: r'\\wsl.localhost\Ubuntu\home\user\repo')),
    );

    expect(find.textContaining('apps/pi_frame/lib/main.dart', findRichText: true), findsWidgets);
    expect(find.textContaining('la guida', findRichText: true), findsWidgets);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
  });

  group('markdown tables', () {
    const table = '| Check | Result |\n| --- | --- |\n| Build | Ready |\n| Tests | Passing |';

    testWidgets('renders a header and body rows as a Table, not raw pipes', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const RichContent(text: table)));

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Check'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.textContaining('|', findRichText: true), findsNothing);
    });

    testWidgets('wide tables scroll horizontally without overflow at 320 px', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const wide =
          '| Column one with a long name | Column two with a long name | Column three | Four |\n'
          '| --- | --- | --- | --- |\n'
          '| a very long cell value that keeps going | another long cell value here | x | y |';
      await tester.pumpWidget(wrapWithTheme(const RichContent(text: wide)));

      expect(find.byType(Table), findsOneWidget);
      expect(tester.takeException(), isNull);
      final horizontal = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((s) => s.scrollDirection == Axis.horizontal);
      expect(horizontal, isNotEmpty);
    });
  });
}

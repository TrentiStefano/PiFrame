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
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
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

  testWidgets('ThinkingBlock disappears completely when thinking text is empty', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        const ThinkingBlock(
          thinkingText: '',
          isStreaming: false,
        ),
      ),
    );

    expect(find.text('Ragionamento'), findsNothing);
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

    await tester.pumpWidget(
      wrapWithTheme(
        const RichContent(text: markdown),
      ),
    );

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

    await tester.pumpWidget(
      wrapWithTheme(
        const RichContent(text: textWithFile, cwd: '/dummy/project'),
      ),
    );

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
    expect(find.byTooltip('CTRL+clic per aprire in Esplora file'), findsWidgets);
  });
}


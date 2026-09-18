import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/features/transcript/rich_content.dart';
import 'package:pi_crust/features/transcript/thinking_block.dart';
import 'package:pi_crust/ui/code/code_block.dart';
import 'package:pi_crust/ui/code/diff_block.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [CrustTokens.dark],
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
}

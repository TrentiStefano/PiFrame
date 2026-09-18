import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust/ui/code/code_block.dart';
import 'package:pi_crust/ui/code/diff_block.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [CrustTokens.dark],
      ),
      home: Scaffold(body: child),
    );
  }

  testWidgets('CodeBlock renders language badge and code content', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        const CodeBlock(
          code: 'final x = 42;\n// comment\nprint(x);',
          language: 'dart',
        ),
      ),
    );

    expect(find.text('DART'), findsOneWidget);
    expect(find.text('Copia'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('DiffBlock parses additions, deletions, and hunk headers correctly', (tester) async {
    const diff = '''
@@ -1,3 +1,4 @@
 context line
-deleted line
+added line
+another addition
''';

    await tester.pumpWidget(
      wrapWithTheme(
        const DiffBlock(
          diffText: diff,
          filename: 'lib/main.dart',
        ),
      ),
    );

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.textContaining('added line'), findsOneWidget);
    expect(find.textContaining('deleted line'), findsOneWidget);
  });
}

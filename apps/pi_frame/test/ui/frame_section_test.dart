import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/frame_section.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(body: child),
      );

  testWidgets('shows title, description and child inside one bordered box', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const FrameSection(
          title: 'Aspetto',
          description: 'Tema e font',
          child: Text('contenuto'),
        ),
      ),
    );

    expect(find.text('Aspetto'), findsOneWidget);
    expect(find.text('Tema e font'), findsOneWidget);
    expect(find.text('contenuto'), findsOneWidget);

    // Title uses the UI face (Schibsted), never the Barlow heading face.
    final title = tester.widget<Text>(find.text('Aspetto'));
    expect(title.style?.fontFamily, FrameTokens.dark.uiFontFamily);

    final box = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('contenuto'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    final side = (decoration.border as Border).top;
    expect(side.color, FrameTokens.dark.border);
    expect(side.width, 1);
  });

  testWidgets('omits the description when none is given', (tester) async {
    await tester.pumpWidget(
      host(const FrameSection(title: 'Solo titolo', child: SizedBox())),
    );
    expect(find.text('Solo titolo'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });
}

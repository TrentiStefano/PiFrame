import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/composer/composer_status_line.dart';
import 'package:pi_frame/features/transcript/subagent_panel.dart';
import 'package:pi_frame/ui/frame_activity_indicator.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Wraps [child] with the platform "reduce motion" flag set.
Widget _reduced(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('activity indicator is static under reduced motion', (tester) async {
    await tester.pumpWidget(
      _reduced(const FrameActivityIndicator(size: 14, color: Colors.white, semanticLabel: 'Working')),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.sync_outlined), findsOneWidget);
    expect(tester.getSize(find.byIcon(Icons.sync_outlined)), const Size(14, 14));
    expect(find.bySemanticsLabel('Working'), findsOneWidget);
  });

  testWidgets('composer run status line shows no spinner under reduced motion', (tester) async {
    await tester.pumpWidget(
      _reduced(
        ComposerRunStatusLine(
          active: true,
          startedAt: null,
          label: 'L\'agente sta rispondendo…',
          interruptLabel: 'Interrompi',
          onInterrupt: () {},
        ),
      ),
    );
    expect(find.text('L\'agente sta rispondendo…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('subagent header dot shows no spinner under reduced motion', (tester) async {
    await tester.pumpWidget(_reduced(const SubagentStatusDot(running: true)));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

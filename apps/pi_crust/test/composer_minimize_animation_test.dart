import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust/data/daemon/daemon_providers.dart';
import 'package:pi_crust/domain/session/session_state.dart';
import 'package:pi_crust/domain/session/agent_status.dart';
import 'package:pi_crust/features/composer/composer.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  Widget wrapComposer({required SessionState state}) {
    return ProviderScope(
      overrides: [
        sessionStateFamily('s_min_test').overrideWith(
          (ref) => SessionStateNotifier('s_min_test', null)..state = state,
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
        home: const Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              Composer(sessionId: 's_min_test'),
            ],
          ),
        ),
      ),
    );
  }

  group('Composer minimize and maximize behavior when agent is answering', () {
    testWidgets('minimizes chat input window when agent is streaming / answering', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      // Should be minimized with compact bar
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);
      expect(find.textContaining('L\'agente sta rispondendo'), findsOneWidget);
      // The full text field input area is minimized
      expect(find.byKey(const ValueKey('composer-input-area')), findsNothing);
    });

    testWidgets('maximizes chat input window when mouse hovers over it', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      // Initially minimized
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);

      // Simulate mouse hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(Composer)));
      await tester.pump(const Duration(milliseconds: 300));

      // Now maximized: full text field and steer/interrupt controls are visible
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.text('Steer'), findsOneWidget);

      // Moving mouse away: during grace period (300ms) it stays open
      await gesture.moveTo(const Offset(10, 10)); // outside composer
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsNothing);

      // After grace period (600ms + animation) expires, it minimizes back
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);
    });

    testWidgets('does not minimize if text has been inputted even if user clicks away while model is generating', (tester) async {
      // Start with settled session
      var sessionNotifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_min_test').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter some text into the composer
      await tester.enterText(find.byKey(const ValueKey('composer-text-field')), 'I have written some instructions here');
      await tester.pumpAndSettle();

      // User unfocuses / clicks away (e.g. tap elsewhere)
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Model starts generating / answering
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer while text was entered...'},
      );
      // Wait past any grace periods / animations
      await tester.pump(const Duration(milliseconds: 1000));

      // Should NOT be minimized because the user wrote text!
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsNothing);
      expect(find.text('I have written some instructions here'), findsOneWidget);
    });

    testWidgets('does not minimize if the input box is focused', (tester) async {
      // Start with settled session
      var sessionNotifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_min_test').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [CrustTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the text field
      await tester.tap(find.byKey(const ValueKey('composer-text-field')));
      await tester.pumpAndSettle();

      // Now agent starts answering / working
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Streaming while focused...'},
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Because input box is focused, it should NOT minimize!
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsNothing);
    });
  });
}

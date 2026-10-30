import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/workspace/pane_drag_state.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  // A long draft wraps differently at each width, so the composer height changes during a drag.
  final longDraft = List.filled(60, 'pane divider resize sample').join(' ');

  Widget tree(ProviderContainer container, double width) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              SizedBox(
                width: width,
                child: const Composer(sessionId: 's_resize'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        sessionStateFamily('s_resize').overrideWith(
          (ref) => SessionStateNotifier('s_resize', null)
            ..state = const SessionState(sessionId: 's_resize', cwd: '/test'),
        ),
      ],
    );
    container.read(composerDraftProvider('s_resize').notifier).state =
        longDraft;
    addTearDown(container.dispose);
    return container;
  }

  Finder composerBox() => find
      .descendant(
        of: find.byType(Composer),
        matching: find.byType(AnimatedContainer),
      )
      .first;

  testWidgets('composer height follows a pane drag without a tween tail', (
    tester,
  ) async {
    final container = makeContainer();
    await tester.pumpWidget(tree(container, 800));
    await tester.pumpAndSettle();

    container.read(paneDraggingProvider.notifier).state = true;
    await tester.pumpWidget(tree(container, 300));
    await tester.pump(const Duration(milliseconds: 16));
    final duringDrag = tester.getSize(composerBox()).height;
    await tester.pumpAndSettle();
    final settled = tester.getSize(composerBox()).height;

    expect(duringDrag, closeTo(settled, 0.5));
  });
}

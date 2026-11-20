import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/composer/composer_focus_provider.dart';
import 'package:pi_frame/features/transcript/empty_chat_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('empty chat requests composer focus once it appears', (
    tester,
  ) async {
    int? requested;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                requested = ref.watch(composerFocusRequestProvider('one'));
                return const EmptyChatView(sessionId: 'one', cwd: '/work/app');
              },
            ),
          ),
        ),
      ),
    );
    expect(requested, 0);
    await tester.pump();
    expect(requested, 1);
    expect(find.byKey(const ValueKey('empty-chat')), findsOneWidget);
  });

  testWidgets('focus request is scoped to the session that is empty', (
    tester,
  ) async {
    int? other;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                other = ref.watch(composerFocusRequestProvider('two'));
                return const EmptyChatView(sessionId: 'one', cwd: '/work/app');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(other, 0);
  });
}

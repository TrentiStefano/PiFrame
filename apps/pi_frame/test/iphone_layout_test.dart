import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/theme/theme_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/ui/shimmer_border.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapApp(Widget child, {bool dark = true, String? activeSessionId, SessionState? sessionState}) {
    final json = File('assets/themes/piframe-${dark ? 'dark' : 'light'}.json').readAsStringSync();
    final repo = ThemeRepository()
      ..registerThemeJson(json)
      ..setActiveTheme(dark ? 'piframe-dark' : 'piframe-light');
    return ProviderScope(
      overrides: [
        themeRepositoryProvider.overrideWithValue(repo),
        daemonEndpointProvider.overrideWith((ref) async => null),
        connectionStateProvider.overrideWith((ref) => Stream.value(DaemonConnectionState.connected)),
        if (activeSessionId != null) activeSessionIdProvider.overrideWith((ref) => activeSessionId),
        if (activeSessionId != null && sessionState != null)
          sessionStateFamily(activeSessionId).overrideWith((ref) {
            final notifier = SessionStateNotifier(activeSessionId, null);
            notifier.state = sessionState;
            return notifier;
          }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: repo.activeTheme.toThemeData(),
        home: child,
      ),
    );
  }

  group('iPhone 12 Layout & Corner Clearance Tests', () {
    testWidgets('AppShell renders on iPhone 12 viewport (390x844) without overflow or clipping', (tester) async {
      // iPhone 12 physical resolution: 1170 x 2532, DPR 3.0 -> logical 390 x 844
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: 141, bottom: 102); // 47pt top, 34pt bottom
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      const session = SessionState(
        sessionId: 'sess_iphone12',
        sessionName: 'Test iPhone 12 Session',
        cwd: '/repo/mobile',
        entries: [
          SessionEntry(
            id: 'e1',
            role: 'user',
            text: 'Hello from iPhone 12 web app!',
            timestamp: 1000,
          ),
          SessionEntry(
            id: 'e2',
            role: 'assistant',
            text: 'Hello! I am formatted for mobile view without corner clipping.',
            timestamp: 1001,
          ),
        ],
      );

      await tester.pumpWidget(wrapApp(
        const AppShell(),
        activeSessionId: 'sess_iphone12',
        sessionState: session,
      ));
      await tester.pumpAndSettle();

      // Ensure no exceptions or render flex overflow
      expect(tester.takeException(), isNull);

      // Verify mobile pane selector is shown
      expect(find.text('Chat'), findsWidgets);

      // Verify composer card is rendered with safe mobile margins
      final composerFinder = find.byType(Composer);
      expect(composerFinder, findsOneWidget);

      final shimmerFinder = find.descendant(
        of: composerFinder,
        matching: find.byType(ShimmerBorder),
      );
      expect(shimmerFinder, findsOneWidget);

      final cardBox = tester.getRect(shimmerFinder);
      // Screen width is 390. Composer card must have safe margins >= 16px from edges
      expect(cardBox.left, greaterThanOrEqualTo(16.0));
      expect(390.0 - cardBox.right, greaterThanOrEqualTo(16.0));

      // Bottom margin must respect safe area home indicator (at least 34px on iPhone 12)
      expect(844.0 - cardBox.bottom, greaterThanOrEqualTo(34.0));
    });

    testWidgets('iPhone 12 with active session and steer queue renders cleanly', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      const session = SessionState(
        sessionId: 'sess_iphone12_streaming',
        sessionName: 'Streaming on iPhone 12',
        cwd: '/repo/mobile',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Processing live answer...'},
        steeringQueue: ['Next direction'],
        entries: [
          SessionEntry(
            id: 'e1',
            role: 'user',
            text: 'Process this request',
            timestamp: 1000,
          ),
        ],
      );

      await tester.pumpWidget(wrapApp(
        const AppShell(),
        activeSessionId: 'sess_iphone12_streaming',
        sessionState: session,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

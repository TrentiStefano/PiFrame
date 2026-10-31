import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/app/app_shell.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';

void main() {
  testWidgets('macOS integrated title bar leaves space for traffic lights and omits Windows caption buttons', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          desktopChromeProvider.overrideWithValue(true),
          desktopWindowLifecycleProvider.overrideWithValue(false),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify 76px spacer for macOS traffic lights is present
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == 76,
        ),
        findsOneWidget,
      );

      // Verify Windows caption buttons are NOT rendered on macOS
      expect(find.byType(DesktopCaptionButtons), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows integrated title bar renders DesktopCaptionButtons and has no 76px spacer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          desktopChromeProvider.overrideWithValue(true),
          desktopWindowLifecycleProvider.overrideWithValue(false),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(DaemonConnectionState.connected),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify 76px spacer for macOS traffic lights is NOT present on Windows
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == 76,
        ),
        findsNothing,
      );

      // Verify DesktopCaptionButtons ARE rendered on Windows
      expect(find.byType(DesktopCaptionButtons), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

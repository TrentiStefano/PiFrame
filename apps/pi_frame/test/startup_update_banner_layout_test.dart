import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/update/startup_updates_provider.dart';
import 'package:pi_frame/features/updates/startup_update_banner.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _FakeChecker implements StartupUpdateChecker {
  @override
  Future<String?> checkCurrentPiVersion() async => '1.3.0';

  @override
  Future<String?> checkLatestPiVersion() async => '1.4.0';

  @override
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async => const [];
}

/// Pumps a shell-like Stack: title bar strip at the top, composer strip at the
/// bottom, and the banner placed the same way the app shell places it.
Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      startupUpdateCheckerProvider.overrideWithValue(_FakeChecker()),
      appLanguageProvider.overrideWith(
        (ref) => AppLanguageNotifier()..setLanguage(AppLanguage.en),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(startupUpdatesProvider.notifier).checkUpdates();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 6,
                left: 8,
                right: 8,
                height: 42,
                child: Container(key: const ValueKey('title_bar_strip')),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 140,
                child: Container(
                  key: const ValueKey('composer_strip'),
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Container(key: const ValueKey('composer_model')),
                      const Spacer(),
                      Container(key: const ValueKey('composer_send')),
                    ],
                  ),
                ),
              ),
              const StartupUpdateBanner(top: 56),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(1584, 991), Size(420, 700)]) {
    testWidgets(
      'startup update banner sits top-right, flat, and clear of the composer '
      'at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpShell(tester, size);

        final banner = find.byType(StartupUpdateBanner);
        expect(banner, findsOneWidget);
        final bannerRect = tester.getRect(
          find.byKey(const ValueKey('startup-update-open-btn')),
        );
        final bannerBox = tester.getRect(
          find.descendant(of: banner, matching: find.byType(Material)).first,
        );

        // Top-right, below the title bar strip.
        final titleRect = tester.getRect(
          find.byKey(const ValueKey('title_bar_strip')),
        );
        expect(bannerBox.top, greaterThanOrEqualTo(titleRect.bottom));
        expect(bannerBox.right, closeTo(size.width - 12, 0.5));
        expect(bannerBox.left, greaterThanOrEqualTo(0));
        expect(bannerBox.width, lessThanOrEqualTo(420));
        expect(bannerRect.right, lessThanOrEqualTo(bannerBox.right));

        // Does not overlap the composer controls.
        for (final key in const [
          ValueKey('composer_model'),
          ValueKey('composer_send'),
        ]) {
          final controlRect = tester.getRect(find.byKey(key));
          expect(
            bannerBox.overlaps(controlRect),
            isFalse,
            reason: 'banner must not cover $key',
          );
        }
        final composerRect = tester.getRect(
          find.byKey(const ValueKey('composer_strip')),
        );
        expect(bannerBox.overlaps(composerRect), isFalse);

        // No elevation or shadow; 1 px border on the surfaceElevated fill.
        final material = tester.widget<Material>(
          find.descendant(of: banner, matching: find.byType(Material)).first,
        );
        expect(material.elevation, 0);
        expect(material.shadowColor, isNull);
        expect(material.color, FrameTokens.dark.surfaceElevated);
        final shape = material.shape as RoundedRectangleBorder;
        expect(shape.side.width, 1);
        expect(shape.side.color, FrameTokens.dark.border);
      },
    );
  }
}

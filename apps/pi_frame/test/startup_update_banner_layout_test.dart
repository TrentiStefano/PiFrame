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
  Future<List<PackageUpdateInfo>> checkOutdatedPackages() async => const [
    PackageUpdateInfo(
      name: 'pi-subagents-with-a-very-long-package-name',
      currentVersion: '1.0.10',
      latestVersion: '1.0.11',
    ),
  ];
}

/// Pumps a shell-like layout under a title bar strip. With [inRail] the
/// sessions rail (banner inline at its top) sits left of the composer; without
/// it the banner is a full-width row directly under the title bar.
Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  required bool inRail,
}) async {
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

  final titleBar = Container(
    key: const ValueKey('title_bar_strip'),
    height: 42,
    margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
  );
  final composer = Container(
    key: const ValueKey('composer_strip'),
    height: 140,
    color: Colors.transparent,
    child: Row(
      children: [
        Container(key: const ValueKey('composer_model')),
        const Spacer(),
        Container(key: const ValueKey('composer_send')),
      ],
    ),
  );

  final body = inRail
      ? Column(
          children: [
            titleBar,
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: Column(
                      children: [
                        const StartupUpdateBanner(inRail: true),
                        Expanded(
                          child: Container(
                            key: const ValueKey('sessions_list'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: composer),
                ],
              ),
            ),
          ],
        )
      : Column(
          children: [
            titleBar,
            const StartupUpdateBanner(),
            const Spacer(),
            composer,
          ],
        );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'startup update banner sits inline at the top of the sessions rail, '
    'flat, and never overlaps other controls',
    (tester) async {
      await _pumpShell(tester, const Size(1584, 991), inRail: true);

      final banner = find.byType(StartupUpdateBanner);
      expect(banner, findsOneWidget);
      final bannerBox = tester.getRect(
        find.descendant(of: banner, matching: find.byType(Material)).first,
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey('title_bar_strip')),
      );
      final railRect = tester.getRect(
        find.byKey(const ValueKey('sessions_list')),
      );
      final composerRect = tester.getRect(
        find.byKey(const ValueKey('composer_strip')),
      );

      // Inside the rail bounds, below the title bar, and above the list.
      expect(bannerBox.left, greaterThanOrEqualTo(0));
      expect(bannerBox.right, lessThanOrEqualTo(260));
      expect(bannerBox.top, greaterThanOrEqualTo(titleRect.bottom));
      expect(bannerBox.bottom, lessThanOrEqualTo(railRect.top));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('startup-update-open-btn')))
            .right,
        lessThanOrEqualTo(bannerBox.right),
      );

      // Does not overlap the title bar, the composer, or its controls.
      expect(bannerBox.overlaps(titleRect), isFalse);
      expect(bannerBox.overlaps(composerRect), isFalse);
      for (final key in const [
        ValueKey('composer_model'),
        ValueKey('composer_send'),
      ]) {
        expect(
          bannerBox.overlaps(tester.getRect(find.byKey(key))),
          isFalse,
          reason: 'banner must not cover $key',
        );
      }

      _expectFlat(tester, banner);
    },
  );

  testWidgets(
    'startup update banner is a full-width inline row under the title bar '
    'when the rail is hidden, and never overlaps the composer',
    (tester) async {
      await _pumpShell(tester, const Size(420, 700), inRail: false);

      final banner = find.byType(StartupUpdateBanner);
      expect(banner, findsOneWidget);
      final bannerBox = tester.getRect(
        find.descendant(of: banner, matching: find.byType(Material)).first,
      );
      final titleRect = tester.getRect(
        find.byKey(const ValueKey('title_bar_strip')),
      );
      final composerRect = tester.getRect(
        find.byKey(const ValueKey('composer_strip')),
      );

      // Directly under the title bar and spanning the window width.
      expect(bannerBox.top, greaterThanOrEqualTo(titleRect.bottom));
      expect(bannerBox.left, closeTo(12, 0.5));
      expect(bannerBox.right, closeTo(420 - 12, 0.5));
      expect(bannerBox.bottom, lessThanOrEqualTo(composerRect.top));
      expect(bannerBox.overlaps(composerRect), isFalse);
      for (final key in const [
        ValueKey('composer_model'),
        ValueKey('composer_send'),
      ]) {
        expect(
          bannerBox.overlaps(tester.getRect(find.byKey(key))),
          isFalse,
          reason: 'banner must not cover $key',
        );
      }

      _expectFlat(tester, banner);
    },
  );
}

void _expectFlat(WidgetTester tester, Finder banner) {
  final material = tester.widget<Material>(
    find.descendant(of: banner, matching: find.byType(Material)).first,
  );
  expect(material.elevation, 0);
  expect(material.shadowColor, isNull);
  expect(material.color, FrameTokens.dark.surfaceElevated);
  final shape = material.shape as RoundedRectangleBorder;
  expect(shape.side.width, 1);
  expect(shape.side.color, FrameTokens.dark.border);
}

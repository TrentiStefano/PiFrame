import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/data/language/strings_settings.dart';
import 'package:pi_frame/features/settings/sections/packages_section.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

const _strings = AppStrings(AppLanguage.en);

Widget _packages({
  required List<Map<String, dynamic>> packages,
  required void Function(Map<String, dynamic>) onUpdate,
  required void Function(Map<String, dynamic>) onPin,
  required void Function(Map<String, dynamic>) onRemove,
}) {
  return MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
    home: Scaffold(
      body: PackagesSection(
        tokens: FrameTokens.dark,
        strings: _strings,
        isLoading: false,
        slow: false,
        loadError: null,
        packages: packages,
        isWorking: false,
        updateProgress: null,
        updateErrorMessage: null,
        onRetry: () {},
        onUpdateAll: () {},
        onUpdatePackage: onUpdate,
        onPinPackage: onPin,
        onRemovePackage: onRemove,
      ),
    ),
  );
}

void main() {
  final outdated = {'name': 'pi-tools', 'source': 'npm:pi-tools', 'version': '1.0.0', 'latestVersion': '2.0.0'};
  final current = {'name': 'pi-notes', 'source': 'npm:pi-notes', 'version': '3.1.0', 'latestVersion': '3.1.0'};

  testWidgets('a package row shows its version and source', (tester) async {
    await tester.pumpWidget(_packages(packages: [current], onUpdate: (_) {}, onPin: (_) {}, onRemove: (_) {}));
    await tester.pump();

    expect(find.textContaining('3.1.0'), findsOneWidget);
    expect(find.textContaining('npm:pi-notes'), findsOneWidget);
  });

  testWidgets('update, pin and remove call back with the package they belong to', (tester) async {
    final updated = <Map<String, dynamic>>[];
    final pinned = <Map<String, dynamic>>[];
    final removed = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      _packages(packages: [outdated], onUpdate: updated.add, onPin: pinned.add, onRemove: removed.add),
    );
    await tester.pump();

    await tester.tap(find.byTooltip(_strings.updatePackageTooltip('pi-tools')));
    await tester.pump();
    await tester.tap(find.byTooltip(_strings.pinPackageTooltip('pi-tools')));
    await tester.pump();
    await tester.tap(find.byTooltip(_strings.removePackageTooltip('pi-tools')));
    await tester.pump();

    expect(updated, [outdated]);
    expect(pinned, [outdated]);
    expect(removed, [outdated]);
  });

  testWidgets('update stays disabled for a package that is already current', (tester) async {
    final updated = <Map<String, dynamic>>[];
    await tester.pumpWidget(_packages(packages: [current], onUpdate: updated.add, onPin: (_) {}, onRemove: (_) {}));
    await tester.pump();

    await tester.tap(find.byTooltip(_strings.updatePackageTooltip('pi-notes')));
    await tester.pump();

    expect(updated, isEmpty);
  });
}

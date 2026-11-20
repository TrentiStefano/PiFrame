import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/features/settings/sections/packages_section.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Pumps the Settings Pacchetti tab with the platform "reduce motion" flag.
Widget _packages({required bool isLoading, required bool isWorking, required double? updateProgress}) {
  const tokens = FrameTokens.dark;
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: PackagesSection(
            tokens: tokens,
            strings: const AppStrings(AppLanguage.en),
            isLoading: isLoading,
            slow: false,
            loadError: null,
            packages: const [],
            isWorking: isWorking,
            updateProgress: updateProgress,
            updateErrorMessage: null,
            onRetry: () {},
            onUpdateAll: () {},
            onUpdatePackage: (_) {},
            onPinPackage: (_) {},
            onRemovePackage: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Pacchetti loading shows no indeterminate indicator under reduced motion', (tester) async {
    await tester.pumpWidget(_packages(isLoading: true, isWorking: false, updateProgress: null));
    expect(find.byKey(const ValueKey('packages-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('Pacchetti update in progress shows no indeterminate bar under reduced motion', (tester) async {
    await tester.pumpWidget(_packages(isLoading: false, isWorking: true, updateProgress: null));
    await tester.pump();
    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    for (final bar in bars) {
      expect(bar.value, isNotNull, reason: 'indeterminate bar still loops');
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

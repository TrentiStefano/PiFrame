import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/motion.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  double contrast(Color a, Color b) {
    final luminanceA = a.computeLuminance();
    final luminanceB = b.computeLuminance();
    return ((luminanceA > luminanceB ? luminanceA : luminanceB) + 0.05) /
        ((luminanceA < luminanceB ? luminanceA : luminanceB) + 0.05);
  }

  for (final variant in ['light', 'dark']) {
    test(
      '$variant uses official PiFrame colors and readable text pairings',
      () {
        final bundled = File('assets/themes/piframe-$variant.json')
            .readAsStringSync();
        final spec = ThemeSpec.fromJson(jsonDecode(bundled));
        final tokens = spec.toTokens();
        final light = variant == 'light';

        expect(tokens.background, Color(light ? 0xFFF1F3F7 : 0xFF161C27));
        expect(tokens.surfaceElevated, Color(light ? 0xFFFFFFFF : 0xFF242E40));
        expect(tokens.accent, Color(light ? 0xFF24638A : 0xFF5F9FC5));
        expect(tokens.success, Color(light ? 0xFF336C42 : 0xFFA1D9B0));
        expect(tokens.warning, Color(light ? 0xFF895706 : 0xFFF6BD53));
        expect(tokens.danger, Color(light ? 0xFF882316 : 0xFFF1887A));
        expect(tokens.info, Color(light ? 0xFF24638A : 0xFF5F9FC5));
        expect(tokens.radiusSm, 6);
        expect(tokens.radiusMd, 10);
        expect(tokens.radiusLg, 14);

        for (final background in [
          tokens.background,
          tokens.surface,
          tokens.surfaceElevated,
          tokens.userBubble,
        ]) {
          for (final foreground in [
            tokens.textPrimary,
            tokens.textSecondary,
          ]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
          expect(contrast(tokens.textMuted, background), greaterThanOrEqualTo(3.0));
        }
        expect(
          contrast(tokens.accentContrast, tokens.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(tokens.displayText, tokens.displaySurface),
          greaterThanOrEqualTo(4.5),
        );
        for (final foreground in [
          tokens.syntaxKeyword,
          tokens.syntaxString,
          tokens.syntaxNumber,
          tokens.syntaxComment,
          tokens.syntaxFunction,
          tokens.syntaxType,
          tokens.syntaxVariable,
          tokens.syntaxOperator,
          tokens.syntaxPunctuation,
          tokens.syntaxInvalid,
        ]) {
          expect(
            contrast(foreground, tokens.surface),
            greaterThanOrEqualTo(4.5),
          );
        }

        expect(
          contrast(tokens.inputBorder, tokens.surface),
          greaterThanOrEqualTo(3.0),
          reason: 'inputBorder must be a 3:1 non-text boundary on surface.',
        );
        expect(
          contrast(tokens.focusRing, tokens.surface),
          greaterThanOrEqualTo(3.0),
        );

        final source = jsonDecode(
          File('../../themes/piframe-$variant.json').readAsStringSync(),
        );
        expect(
          source,
          jsonDecode(bundled),
          reason: 'Source and bundled themes must stay synchronized.',
        );
        expect(tokens.uiFontFamily, 'SchibstedGrotesk');
        expect(tokens.headingFontFamily, 'BarlowCondensed');
        expect(tokens.monoFontFamily, 'SourceCodePro');
      },
    );
  }

  test('spacing and size scales are fixed constants', () {
    expect(
      [FrameSpace.x1, FrameSpace.x2, FrameSpace.x3, FrameSpace.x4, FrameSpace.x6, FrameSpace.x8],
      [4, 8, 12, 16, 24, 32],
    );
    expect(FrameSize.rowList, 28);
    expect(FrameSize.rowForm, 40);
    expect(FrameSize.hitMin, 28);
    expect(FrameSize.icon, 16);
    expect(FrameSize.iconLg, 20);
    expect(FrameSize.paneHeader, 40);
  });

  test('FrameMotion and FrameTokens read the same motion constants', () {
    expect(FrameMotion.micro, FrameTokens.dark.pressDuration);
    expect(FrameMotion.micro, FrameTokens.light.pressDuration);
    expect(FrameMotion.panel, FrameTokens.dark.panelDuration);
    expect(FrameMotion.panel, FrameTokens.light.panelDuration);
    expect(FrameMotion.enterCurve, FrameTokens.dark.enterCurve);
    expect(FrameMotion.panelCurve, FrameTokens.dark.panelCurve);
    expect(FrameMotion.instant, Duration.zero);
    expect(FrameMotion.smallExit, const Duration(milliseconds: 120));
    expect(FrameMotion.panelExit, const Duration(milliseconds: 180));
    expect(FrameMotion.dialog, const Duration(milliseconds: 180));
    expect(FrameMotion.dialogExit, const Duration(milliseconds: 120));
    expect(FrameMotion.firstRun, const Duration(milliseconds: 300));
    expect(FrameMotion.stagger, const Duration(milliseconds: 100));
  });

  testWidgets('FrameText roles come from the theme fonts with an 11 px floor', (tester) async {
    final spec = ThemeSpec.fromJson(
      jsonDecode(File('assets/themes/piframe-dark.json').readAsStringSync()),
    );
    late FrameText text;
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.toThemeData(),
        home: Builder(
          builder: (context) {
            text = FrameText.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    for (final style in [
      text.caption,
      text.label,
      text.body,
      text.bodyLarge,
      text.title,
      text.heading,
      text.display,
      text.mono,
      text.monoBody,
    ]) {
      expect(style.fontSize, greaterThanOrEqualTo(11));
    }
    expect(text.caption.fontSize, 11);
    expect(text.caption.height! * text.caption.fontSize!, closeTo(16, 0.01));
    expect(text.body.height! * text.body.fontSize!, closeTo(20, 0.01));
    expect(text.display.height! * text.display.fontSize!, closeTo(32, 0.01));
    expect(text.caption.fontFamily, 'SchibstedGrotesk');
    expect(text.label.fontFamily, 'SchibstedGrotesk');
    expect(text.mono.fontFamily, 'SourceCodePro');
    expect(text.monoBody.fontFamily, 'SourceCodePro');
  });

  test('themes without an inputBorder derive one with 3:1 contrast', () {
    final legacy = ThemeSpec(
      id: 'legacy-dark',
      name: 'Legacy Dark',
      variant: 'dark',
      rawColors: {
        'surface': '#181825',
        'borderStrong': '#585b70',
        'textPrimary': '#cdd6f4',
      },
    ).toTokens();
    expect(frameContrastRatio(legacy.inputBorder, legacy.surface), greaterThanOrEqualTo(3.0));
  });
}

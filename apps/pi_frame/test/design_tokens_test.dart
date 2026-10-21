import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

        expect(tokens.background, Color(light ? 0xFFF4F5F8 : 0xFF161C27));
        expect(tokens.surfaceElevated, Color(light ? 0xFFFFFFFF : 0xFF242E40));
        expect(tokens.accent, Color(light ? 0xFF24638A : 0xFF5898BD));
        expect(tokens.success, Color(light ? 0xFF15803D : 0xFF4ADE80));
        expect(tokens.warning, Color(light ? 0xFFA15C0D : 0xFFF6BD53));
        expect(tokens.danger, Color(light ? 0xFFB92F24 : 0xFFF1887A));
        expect(tokens.info, Color(light ? 0xFF24638A : 0xFF5898BD));
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
            tokens.textMuted,
          ]) {
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
          }
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
}

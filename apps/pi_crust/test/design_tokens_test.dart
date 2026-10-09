import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  double contrast(Color a, Color b) {
    final luminanceA = a.computeLuminance();
    final luminanceB = b.computeLuminance();
    return ((luminanceA > luminanceB ? luminanceA : luminanceB) + 0.05) /
        ((luminanceA < luminanceB ? luminanceA : luminanceB) + 0.05);
  }

  for (final variant in ['light', 'dark']) {
    test(
      '$variant uses official Catppuccin colors and readable text pairings',
      () {
        final bundled = File('assets/themes/crust-$variant.json')
            .readAsStringSync();
        final spec = ThemeSpec.fromJson(jsonDecode(bundled));
        final tokens = spec.toTokens();
        final light = variant == 'light';

        expect(tokens.background, Color(light ? 0xFFEFF1F5 : 0xFF303446));
        expect(tokens.surfaceElevated, Color(light ? 0xFFE6E9EF : 0xFF414559));
        expect(tokens.accent, Color(light ? 0xFF8839EF : 0xFFCA9EE6));
        expect(tokens.success, Color(light ? 0xFF40A02B : 0xFFA6D189));
        expect(tokens.warning, Color(light ? 0xFFDF8E1D : 0xFFE5C890));
        expect(tokens.danger, Color(light ? 0xFFD20F39 : 0xFFE78284));
        expect(tokens.info, Color(light ? 0xFF1E66F5 : 0xFF8CAAEE));
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
          File('../../themes/crust-$variant.json').readAsStringSync(),
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

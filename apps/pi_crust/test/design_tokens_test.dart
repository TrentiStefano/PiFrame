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
    test('$variant text, actions, syntax, and status colors meet AA', () {
      final spec = ThemeSpec.fromJson(
        jsonDecode(
          File('assets/themes/crust-$variant.json').readAsStringSync(),
        ),
      );
      final tokens = spec.toTokens();
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
          tokens.accent,
        ]) {
          expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        contrast(tokens.accentContrast, tokens.accent),
        greaterThanOrEqualTo(4.5),
      );
      for (final foreground in [
        tokens.success,
        tokens.warning,
        tokens.danger,
        tokens.info,
        tokens.thinking,
      ]) {
        final tint = Color.alphaBlend(
          foreground.withValues(alpha: 0.12),
          tokens.surface,
        );
        expect(contrast(foreground, tint), greaterThanOrEqualTo(4.5));
      }
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
      ]) {
        expect(contrast(foreground, tokens.surface), greaterThanOrEqualTo(4.5));
      }
      expect(spec.toThemeData().textSelectionTheme.cursorColor, tokens.accent);
      final source = jsonDecode(
        File('../../themes/crust-$variant.json').readAsStringSync(),
      );
      expect(
        source,
        jsonDecode(
          File('assets/themes/crust-$variant.json').readAsStringSync(),
        ),
        reason: 'Source themes and bundled assets must stay in sync',
      );
      expect(tokens.uiFontFamily, 'SchibstedGrotesk');
      expect(tokens.headingFontFamily, 'BarlowCondensed');
      expect(
        contrast(tokens.displayText, tokens.displaySurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(tokens.monoFontFamily, 'SourceCodePro');
    });
  }
}

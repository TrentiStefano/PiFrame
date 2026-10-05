import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  test('CrustTokens dark has required color values', () {
    const tokens = CrustTokens.dark;
    expect(tokens.background, const Color(0xFF151916));
    expect(tokens.accent, const Color(0xFF83CCA1));
    expect(tokens.agentWorking, const Color(0xFF83CCA1));
    expect(tokens.diffAddedBg, const Color(0xFF223D2C));
    expect(tokens.diffAddedFg, const Color(0xFF9BD8B2));
    expect(tokens.syntaxKeyword, const Color(0xFFFFB2AA));
  });

  test('CrustTokens light has required color values', () {
    const tokens = CrustTokens.light;
    expect(tokens.background, const Color(0xFFF8F9F5));
    expect(tokens.surface, const Color(0xFFF8F9F5));
    expect(tokens.accent, const Color(0xFF0D703F));
    expect(tokens.diffAddedBg, const Color(0xFFDDEBDD));
  });

  test('parseHexColor handles 7-char and 9-char hex correctly', () {
    final c1 = parseHexColor('#FF0000');
    expect(c1, const Color(0xFFFF0000));

    // #RRGGBBAA in CSS/JSON format: Red=00, Green=FF, Blue=00, Alpha=80
    final c2 = parseHexColor('#00FF0080');
    expect(c2, const Color(0x8000FF00));
  });

  test('ThemeSpec.fromJson tolerant parsing: malformed color and unknown keys produce warnings, not crash', () {
    final rawJson = {
      'schemaVersion': 1,
      'id': 'test-tolerant',
      'name': 'Test Tolerant',
      'variant': 'dark',
      'unknownKey': 'should be ignored with diagnostic',
      'colors': {'accent': 'not-a-color'},
    };

    final spec = ThemeSpec.fromJson(rawJson);
    expect(spec.id, 'test-tolerant');
    expect(
      spec.diagnostics.any(
        (d) => d.contains('Unknown theme property ignored: "unknownKey"'),
      ),
      isTrue,
    );

    final tokens = spec.toTokens();
    expect(tokens.accent, CrustTokens.dark.accent); // fell back safely!
    expect(
      spec.diagnostics.any(
        (d) => d.contains('Invalid color format for "colors.accent"'),
      ),
      isTrue,
    );
  });

  test('ThemeSpec.merge correctly merges base and override', () {
    final base = ThemeSpec(
      id: 'base',
      name: 'Base Theme',
      variant: 'dark',
      rawColors: {'accent': '#7C9CFF', 'background': '#0E1116'},
    );

    final override = ThemeSpec(
      id: 'override',
      name: 'Override Theme',
      variant: 'dark',
      extendsTheme: 'base',
      rawColors: {'accent': '#FFB84D'},
    );

    final merged = ThemeSpec.merge(base, override);
    expect(merged.id, 'override');
    expect(merged.rawColors['accent'], '#FFB84D');
    expect(merged.rawColors['background'], '#0E1116');
  });

  test('ThemeRepository resolves extends chain and detects cycles', () {
    final repo = ThemeRepository();

    final themeA = jsonEncode({
      'schemaVersion': 1,
      'id': 'theme-a',
      'name': 'Theme A',
      'variant': 'dark',
      'extends': 'theme-b',
    });

    final themeB = jsonEncode({
      'schemaVersion': 1,
      'id': 'theme-b',
      'name': 'Theme B',
      'variant': 'dark',
      'extends': 'theme-a', // Cycle!
    });

    repo.registerThemeJson(themeA);
    repo.registerThemeJson(themeB);

    final resolvedA = repo.availableThemes.firstWhere((t) => t.id == 'theme-a');
    expect(
      resolvedA.diagnostics.any((d) => d.contains('Inheritance cycle')),
      isTrue,
    );
  });

  test('ThemeSpec.toThemeData generates consistent ThemeData with tokens extension', () {
    final spec = ThemeSpec(
      id: 'custom',
      name: 'Custom Theme',
      variant: 'dark',
      rawColors: {'accent': '#7C9CFF', 'background': '#0E1116'},
    );

    final themeData = spec.toThemeData();
    expect(themeData.brightness, Brightness.dark);
    expect(themeData.scaffoldBackgroundColor, const Color(0xFF0E1116));
    expect(themeData.extension<CrustTokens>(), isNotNull);
  });
}

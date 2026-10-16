import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

void main() {
  test(
    'Catppuccin Frappé fallback uses semantic colors and rounded tokens',
    () {
      const tokens = CrustTokens.dark;
      expect(tokens.background, const Color(0xFF303446));
      expect(tokens.surfaceElevated, const Color(0xFF414559));
      expect(tokens.displaySurface, const Color(0xFF414559));
      expect(tokens.displayText, const Color(0xFFC6D0F5));
      expect(tokens.accent, const Color(0xFFCA9EE6));
      expect(tokens.agentWorking, const Color(0xFFA6D189));
      expect(tokens.diffAddedFg, const Color(0xFFA6D189));
      expect(tokens.danger, const Color(0xFFE78284));
      expect(tokens.syntaxKeyword, const Color(0xFFCA9EE6));
      expect(tokens.radiusLg, 14);
    },
  );

  test('Catppuccin Latte fallback has coordinated light surfaces', () {
    const tokens = CrustTokens.light;
    expect(tokens.background, const Color(0xFFEFF1F5));
    expect(tokens.surface, const Color(0xFFEFF1F5));
    expect(tokens.displaySurface, const Color(0xFFCCD0DA));
    expect(tokens.displayText, const Color(0xFF4C4F69));
    expect(tokens.accent, const Color(0xFF8839EF));
    expect(tokens.warning, const Color(0xFFDF8E1D));
    expect(tokens.diffAddedFg, const Color(0xFF216D18));
    expect(tokens.radiusLg, 14);
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
    expect(themeData.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(themeData.snackBarTheme.backgroundColor, spec.toTokens().surfaceElevated);
  });

  test('VsCodeThemeConverter parses VSCode theme JSON with comments and trailing commas', () {
    const vscodeJson = '''
    // Single line comment
    {
      "name": "One Dark Custom",
      "type": "dark",
      "colors": {
        "editor.background": "#282c34",
        "editor.foreground": "#abb2bf",
        "activityBar.background": "#21252b",
        "sideBar.background": "#21252b",
        "focusBorder": "#528bff",
        /* block comment */
        "editorError.foreground": "#e06c75",
        "terminal.ansiGreen": "#98c379",
      },
      "tokenColors": [
        {
          "name": "Keywords",
          "scope": ["keyword", "storage.type"],
          "settings": {
            "foreground": "#c678dd"
          }
        },
        {
          "name": "Strings",
          "scope": "string",
          "settings": {
            "foreground": "#98c379"
          }
        }
      ]
    }
    ''';

    final spec = VsCodeThemeConverter.parseAnyThemeJson(vscodeJson);
    expect(spec.name, 'One Dark Custom');
    expect(spec.variant, 'dark');
    expect(spec.id, 'vscode-one-dark-custom');
    final tokens = spec.toTokens();
    expect(tokens.background, const Color(0xFF282C34));
    expect(tokens.textPrimary, const Color(0xFFABB2BF));
    expect(tokens.syntaxKeyword, const Color(0xFFC678DD));
    expect(tokens.syntaxString, const Color(0xFF98C379));
    expect(tokens.accent, const Color(0xFF528BFF));
  });

  test('VsCodeThemeConverter handles light themes correctly', () {
    const lightJson = '''
    {
      "name": "GitHub Light",
      "type": "light",
      "colors": {
        "editor.background": "#ffffff",
        "editor.foreground": "#24292e",
        "sideBar.background": "#f6f8fa"
      }
    }
    ''';
    final spec = VsCodeThemeConverter.parseAnyThemeJson(lightJson);
    expect(spec.variant, 'light');
    expect(spec.toTokens().background, const Color(0xFFFFFFFF));
    expect(spec.toTokens().textPrimary, const Color(0xFF24292E));
  });
}

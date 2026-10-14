import 'dart:convert';
import 'package:flutter/material.dart';

import 'theme_spec.dart';
import 'theme_tokens.dart';

class VsCodeThemeConverter {
  /// Strips line (`//`) and block (`/* */`) comments as well as trailing commas
  /// from JSONC strings so [jsonDecode] can safely parse VSCode theme JSONs.
  static String stripJsonComments(String input) {
    final buffer = StringBuffer();
    var inString = false;
    var isEscaped = false;
    var inLineComment = false;
    var inBlockComment = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      final nextChar = (i + 1 < input.length) ? input[i + 1] : '';

      if (inLineComment) {
        if (char == '\n' || char == '\r') {
          inLineComment = false;
          buffer.write(char);
        }
        continue;
      }

      if (inBlockComment) {
        if (char == '*' && nextChar == '/') {
          inBlockComment = false;
          i++; // skip /
        }
        continue;
      }

      if (inString) {
        buffer.write(char);
        if (isEscaped) {
          isEscaped = false;
        } else if (char == r'\') {
          isEscaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        buffer.write(char);
        continue;
      }

      if (char == '/' && nextChar == '/') {
        inLineComment = true;
        i++; // skip second /
        continue;
      }

      if (char == '/' && nextChar == '*') {
        inBlockComment = true;
        i++; // skip *
        continue;
      }

      buffer.write(char);
    }

    // Remove trailing commas before } or ]
    return buffer.toString().replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (m) => m.group(1)!,
    );
  }

  /// Parses either a Pi-Crust theme JSON or a VSCode theme JSON (with JSONC comment support).
  static ThemeSpec parseAnyThemeJson(String jsonString) {
    final cleanJson = stripJsonComments(jsonString);
    final dynamic decoded = jsonDecode(cleanJson);
    if (decoded is! Map<String, dynamic> && decoded is! Map) {
      throw const FormatException('Il JSON del tema deve essere un oggetto');
    }

    final map = (decoded is Map<String, dynamic>)
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);

    // Check if it's already a Pi-Crust theme
    final colors = map['colors'];
    final isPiCrustTheme = map.containsKey('id') &&
        (map.containsKey('schemaVersion') ||
            (colors is Map &&
                (colors.containsKey('chassis') ||
                    colors.containsKey('displaySurface'))));

    if (isPiCrustTheme) {
      return ThemeSpec.fromJson(map);
    }

    // Convert from VSCode theme format
    return convertVsCodeTheme(json: map);
  }

  /// Converts a parsed VSCode color theme map into a [ThemeSpec].
  static ThemeSpec convertVsCodeTheme({
    required Map<String, dynamic> json,
    String? overrideId,
  }) {
    final rawName = (json['name']?.toString() ?? 'Tema VSCode').trim();
    final sanitizedBase = rawName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final id = overrideId ??
        (sanitizedBase.isEmpty ? 'vscode-theme' : 'vscode-$sanitizedBase');

    final author = json['author']?.toString() ??
        json['publisher']?.toString() ??
        'VSCode Import';

    final colors = (json['colors'] is Map)
        ? Map<String, dynamic>.from(json['colors'] as Map)
        : <String, dynamic>{};

    String? getFirstColor(List<String> keys) {
      for (final k in keys) {
        final v = colors[k];
        if (v is String && v.trim().isNotEmpty) {
          final trimmed = v.trim();
          if (trimmed.startsWith('#')) return trimmed;
        }
      }
      return null;
    }

    // Determine variant (light vs dark)
    var variant = 'dark';
    final type = json['type']?.toString().toLowerCase();
    if (type == 'light' || type == 'hclight') {
      variant = 'light';
    } else if (type == null) {
      final editorBg = getFirstColor(['editor.background', 'sideBar.background']);
      if (editorBg != null) {
        final c = parseHexColor(editorBg);
        if (c != null && ThemeData.estimateBrightnessForColor(c) == Brightness.light) {
          variant = 'light';
        }
      }
    }

    final isLight = variant == 'light';
    final fallback = isLight ? CrustTokens.light : CrustTokens.dark;

    String hex(Color c) =>
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

    // Workbench surfaces
    final bg = getFirstColor(['editor.background', 'sideBar.background']) ??
        hex(fallback.background);
    final chassis = getFirstColor([
          'activityBar.background',
          'sideBar.background',
          'titleBar.activeBackground',
        ]) ??
        bg;
    final surface = getFirstColor([
          'sideBar.background',
          'editorWidget.background',
          'panel.background',
        ]) ??
        bg;
    final surfaceElevated = getFirstColor([
          'editorWidget.background',
          'dropdown.background',
          'menu.background',
          'quickInput.background',
          'sideBar.background',
        ]) ??
        surface;

    final overlay = getFirstColor([
          'editorOverviewRuler.background',
          'editorHoverWidget.background',
        ]) ??
        (isLight ? '#dce0e8b3' : '#232634b3');

    // Borders
    final border = getFirstColor([
          'sideBar.border',
          'editorGroup.border',
          'panel.border',
          'widget.border',
          'input.border',
        ]) ??
        hex(fallback.border);
    final borderStrong = getFirstColor([
          'focusBorder',
          'sideBar.border',
          'editorGroup.border',
        ]) ??
        hex(fallback.borderStrong);

    // Typography & Text
    final textPrimary = getFirstColor(['editor.foreground', 'foreground']) ??
        hex(fallback.textPrimary);
    final textSecondary = getFirstColor([
          'descriptionForeground',
          'sideBarTitle.foreground',
          'tab.inactiveForeground',
        ]) ??
        hex(fallback.textSecondary);
    final textMuted = getFirstColor([
          'editorLineNumber.foreground',
          'disabledForeground',
          'sideBarTitle.foreground',
        ]) ??
        textSecondary;

    // Accent
    final accent = getFirstColor([
          'focusBorder',
          'activityBarBadge.background',
          'button.background',
          'textLink.foreground',
        ]) ??
        hex(fallback.accent);
    final accentContrast = getFirstColor([
          'button.foreground',
          'activityBarBadge.foreground',
        ]) ??
        hex(fallback.accentContrast);

    // Status indicators
    final success = getFirstColor([
          'terminal.ansiGreen',
          'gitDecoration.addedResourceForeground',
        ]) ??
        hex(fallback.success);
    final warning = getFirstColor([
          'editorWarning.foreground',
          'terminal.ansiYellow',
        ]) ??
        hex(fallback.warning);
    final danger = getFirstColor([
          'editorError.foreground',
          'errorForeground',
          'terminal.ansiRed',
        ]) ??
        hex(fallback.danger);
    final info = getFirstColor([
          'editorInfo.foreground',
          'terminal.ansiBlue',
        ]) ??
        hex(fallback.info);

    // Diff colors
    final diffAddedBg = getFirstColor([
          'diffEditor.insertedTextBackground',
          'diffEditor.insertedLineBackground',
        ]) ??
        (isLight ? '#40a02b26' : '#a6d18926');
    final diffRemovedBg = getFirstColor([
          'diffEditor.removedTextBackground',
          'diffEditor.removedLineBackground',
        ]) ??
        (isLight ? '#d20f3926' : '#e7828426');

    // Syntax Highlighting from tokenColors
    final syntax = <String, dynamic>{};
    final tokenColors = json['tokenColors'];
    if (tokenColors is List) {
      for (final item in tokenColors) {
        if (item is Map) {
          final settings = item['settings'];
          if (settings is Map && settings['foreground'] is String) {
            final fg = (settings['foreground'] as String).trim();
            if (fg.startsWith('#')) {
              final scope = item['scope'];
              final scopes = <String>[];
              if (scope is String) {
                scopes.addAll(scope.split(',').map((s) => s.trim()));
              } else if (scope is List) {
                scopes.addAll(scope.map((s) => s.toString().trim()));
              }

              for (final sc in scopes) {
                final sLower = sc.toLowerCase();
                if (sLower.contains('keyword') || sLower.contains('storage')) {
                  syntax.putIfAbsent('keyword', () => fg);
                } else if (sLower.contains('string')) {
                  syntax.putIfAbsent('string', () => fg);
                } else if (sLower.contains('number') ||
                    sLower.contains('numeric') ||
                    sLower.contains('constant.numeric')) {
                  syntax.putIfAbsent('number', () => fg);
                } else if (sLower.contains('comment')) {
                  syntax.putIfAbsent('comment', () => fg);
                } else if (sLower.contains('function') ||
                    sLower.contains('entity.name.function')) {
                  syntax.putIfAbsent('function', () => fg);
                } else if (sLower.contains('type') ||
                    sLower.contains('class') ||
                    sLower.contains('entity.name.type')) {
                  syntax.putIfAbsent('type', () => fg);
                } else if (sLower.contains('variable')) {
                  syntax.putIfAbsent('variable', () => fg);
                } else if (sLower.contains('operator')) {
                  syntax.putIfAbsent('operator', () => fg);
                } else if (sLower.contains('punctuation')) {
                  syntax.putIfAbsent('punctuation', () => fg);
                } else if (sLower.contains('invalid')) {
                  syntax.putIfAbsent('invalid', () => fg);
                }
              }
            }
          }
        }
      }
    }

    // Fallbacks for syntax
    syntax.putIfAbsent('keyword', () => hex(fallback.syntaxKeyword));
    syntax.putIfAbsent('string', () => hex(fallback.syntaxString));
    syntax.putIfAbsent('number', () => hex(fallback.syntaxNumber));
    syntax.putIfAbsent('comment', () => hex(fallback.syntaxComment));
    syntax.putIfAbsent('function', () => hex(fallback.syntaxFunction));
    syntax.putIfAbsent('type', () => hex(fallback.syntaxType));
    syntax.putIfAbsent('variable', () => hex(fallback.syntaxVariable));
    syntax.putIfAbsent('operator', () => hex(fallback.syntaxOperator));
    syntax.putIfAbsent('punctuation', () => hex(fallback.syntaxPunctuation));
    syntax.putIfAbsent('invalid', () => hex(fallback.syntaxInvalid));

    return ThemeSpec(
      schemaVersion: 1,
      id: id,
      name: rawName.isNotEmpty ? rawName : 'Tema VSCode',
      author: author,
      version: json['version']?.toString() ?? '1.0.0',
      variant: variant,
      rawColors: {
        'background': bg,
        'chassis': chassis,
        'surface': surface,
        'surfaceElevated': surfaceElevated,
        'displaySurface': surfaceElevated,
        'displayText': textPrimary,
        'overlay': overlay,
        'border': border,
        'borderStrong': borderStrong,
        'textPrimary': textPrimary,
        'textSecondary': textSecondary,
        'textMuted': textMuted,
        'accent': accent,
        'accentContrast': accentContrast,
        'focusRing': accent,
        'success': success,
        'warning': warning,
        'danger': danger,
        'info': info,
        'agentWorking': success,
        'agentRetrying': warning,
        'agentCompacting': info,
        'agentSettled': success,
        'agentAwaitingUser': warning,
        'agentError': danger,
        'userBubble': surfaceElevated,
        'thinking': textSecondary,
        'diffAddedBg': diffAddedBg,
        'diffAddedFg': textPrimary,
        'diffRemovedBg': diffRemovedBg,
        'diffRemovedFg': textPrimary,
        'diffContextFg': textSecondary,
      },
      rawSyntax: syntax,
    );
  }
}

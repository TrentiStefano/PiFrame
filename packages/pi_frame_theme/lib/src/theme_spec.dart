import 'package:flutter/material.dart';

import 'theme_tokens.dart';

Color? parseHexColor(
  dynamic hex, {
  Color? fallback,
  String? fieldName,
  List<String>? diagnostics,
}) {
  if (hex == null || hex is! String) {
    return fallback;
  }
  final clean = hex.trim();
  if (!clean.startsWith('#')) {
    diagnostics?.add(
      'Invalid color format for "$fieldName": "$hex". Expected "#RRGGBB" or "#RRGGBBAA". Using fallback.',
    );
    return fallback;
  }
  try {
    if (clean.length == 7) {
      // #RRGGBB
      final val = int.parse(clean.substring(1), radix: 16);
      return Color(0xFF000000 | val);
    } else if (clean.length == 9) {
      // #RRGGBBAA -> RGBA
      final r = int.parse(clean.substring(1, 3), radix: 16);
      final g = int.parse(clean.substring(3, 5), radix: 16);
      final b = int.parse(clean.substring(5, 7), radix: 16);
      final a = int.parse(clean.substring(7, 9), radix: 16);
      return Color.fromARGB(a, r, g, b);
    } else {
      diagnostics?.add(
        'Invalid color length for "$fieldName": "$hex". Expected 7 or 9 chars. Using fallback.',
      );
      return fallback;
    }
  } catch (e) {
    diagnostics?.add(
      'Malformed color hex for "$fieldName": "$hex" ($e). Using fallback.',
    );
    return fallback;
  }
}

class ThemeSpec {
  final int schemaVersion;
  final String id;
  final String name;
  final String author;
  final String version;
  final String variant; // 'dark' | 'light'
  final String? extendsTheme;
  final Map<String, dynamic> rawColors;
  final Map<String, dynamic> rawSyntax;
  final Map<String, dynamic> rawTypography;
  final Map<String, dynamic> rawSpacing;
  final Map<String, dynamic> rawRadii;
  final Map<String, dynamic> rawElevation;
  final Map<String, dynamic> rawMotion;
  final Map<String, dynamic> rawComponents;
  final List<String> diagnostics;

  ThemeSpec({
    this.schemaVersion = 1,
    required this.id,
    required this.name,
    this.author = '',
    this.version = '1.0.0',
    this.variant = 'dark',
    this.extendsTheme,
    this.rawColors = const {},
    this.rawSyntax = const {},
    this.rawTypography = const {},
    this.rawSpacing = const {},
    this.rawRadii = const {},
    this.rawElevation = const {},
    this.rawMotion = const {},
    this.rawComponents = const {},
    List<String>? diagnostics,
  }) : diagnostics = diagnostics ?? [];

  factory ThemeSpec.fromJson(Map<String, dynamic> json) {
    final diagnostics = <String>[];

    const knownKeys = {
      '\$schema',
      'schemaVersion',
      'id',
      'name',
      'author',
      'version',
      'variant',
      'extends',
      'colors',
      'syntax',
      'typography',
      'spacing',
      'radii',
      'elevation',
      'motion',
      'components',
    };

    for (final key in json.keys) {
      if (!knownKeys.contains(key)) {
        diagnostics.add('Unknown theme property ignored: "$key"');
      }
    }

    final schemaVer = json['schemaVersion'] is int
        ? json['schemaVersion'] as int
        : 1;
    final id = json['id'] is String ? json['id'] as String : 'unknown-theme';
    final name = json['name'] is String ? json['name'] as String : id;
    final author = json['author'] is String ? json['author'] as String : '';
    final version = json['version'] is String
        ? json['version'] as String
        : '1.0.0';
    final variant = (json['variant'] == 'light') ? 'light' : 'dark';
    final extendsTheme = json['extends'] is String
        ? json['extends'] as String
        : null;

    Map<String, dynamic> toMap(dynamic val) => (val is Map<String, dynamic>)
        ? val
        : (val is Map)
        ? Map<String, dynamic>.from(val)
        : {};

    return ThemeSpec(
      schemaVersion: schemaVer,
      id: id,
      name: name,
      author: author,
      version: version,
      variant: variant,
      extendsTheme: extendsTheme,
      rawColors: toMap(json['colors']),
      rawSyntax: toMap(json['syntax']),
      rawTypography: toMap(json['typography']),
      rawSpacing: toMap(json['spacing']),
      rawRadii: toMap(json['radii']),
      rawElevation: toMap(json['elevation']),
      rawMotion: toMap(json['motion']),
      rawComponents: toMap(json['components']),
      diagnostics: diagnostics,
    );
  }

  static ThemeSpec merge(ThemeSpec base, ThemeSpec override) {
    final mergedDiagnostics = <String>[
      ...base.diagnostics,
      ...override.diagnostics,
    ];

    Map<String, dynamic> mergeMaps(
      Map<String, dynamic> b,
      Map<String, dynamic> o,
    ) {
      final res = Map<String, dynamic>.from(b);
      res.addAll(o);
      return res;
    }

    return ThemeSpec(
      schemaVersion: override.schemaVersion,
      id: override.id,
      name: override.name,
      author: override.author.isNotEmpty ? override.author : base.author,
      version: override.version.isNotEmpty ? override.version : base.version,
      variant: override.variant,
      extendsTheme: override.extendsTheme,
      rawColors: mergeMaps(base.rawColors, override.rawColors),
      rawSyntax: mergeMaps(base.rawSyntax, override.rawSyntax),
      rawTypography: mergeMaps(base.rawTypography, override.rawTypography),
      rawSpacing: mergeMaps(base.rawSpacing, override.rawSpacing),
      rawRadii: mergeMaps(base.rawRadii, override.rawRadii),
      rawElevation: mergeMaps(base.rawElevation, override.rawElevation),
      rawMotion: mergeMaps(base.rawMotion, override.rawMotion),
      rawComponents: mergeMaps(base.rawComponents, override.rawComponents),
      diagnostics: mergedDiagnostics,
    );
  }

  FrameTokens toTokens() {
    final baseTokens = variant == 'light'
        ? FrameTokens.light
        : FrameTokens.dark;
    final d = diagnostics;

    Color c(String key, Color fallback) => parseHexColor(
      rawColors[key],
      fallback: fallback,
      fieldName: 'colors.$key',
      diagnostics: d,
    )!;

    Color s(String key, Color fallback) => parseHexColor(
      rawSyntax[key],
      fallback: fallback,
      fieldName: 'syntax.$key',
      diagnostics: d,
    )!;

    double numVal(dynamic val, double fallback) {
      if (val is num) return val.toDouble();
      return fallback;
    }

    final uiFont = rawTypography['uiFontFamily'] is String
        ? rawTypography['uiFontFamily'] as String
        : baseTokens.uiFontFamily;
    final monoFont = rawTypography['monoFontFamily'] is String
        ? rawTypography['monoFontFamily'] as String
        : baseTokens.monoFontFamily;

    final rSm = numVal(rawRadii['sm'], baseTokens.radiusSm);
    final rMd = numVal(rawRadii['md'], baseTokens.radiusMd);
    final rLg = numVal(rawRadii['lg'], baseTokens.radiusLg);
    final rPill = numVal(rawRadii['pill'], baseTokens.radiusPill);

    return FrameTokens(
      background: c('background', baseTokens.background),
      surface: c('surface', baseTokens.surface),
      surfaceElevated: c('surfaceElevated', baseTokens.surfaceElevated),
      overlay: c('overlay', baseTokens.overlay),
      border: c('border', baseTokens.border),
      borderStrong: c('borderStrong', baseTokens.borderStrong),
      textPrimary: c('textPrimary', baseTokens.textPrimary),
      textSecondary: c('textSecondary', baseTokens.textSecondary),
      textMuted: c('textMuted', baseTokens.textMuted),
      accent: c('accent', baseTokens.accent),
      accentContrast: c('accentContrast', baseTokens.accentContrast),
      focusRing: c('focusRing', baseTokens.focusRing),
      success: c('success', baseTokens.success),
      warning: c('warning', baseTokens.warning),
      danger: c('danger', baseTokens.danger),
      info: c('info', baseTokens.info),
      agentWorking: c('agentWorking', baseTokens.agentWorking),
      agentRetrying: c('agentRetrying', baseTokens.agentRetrying),
      agentCompacting: c('agentCompacting', baseTokens.agentCompacting),
      agentSettled: c('agentSettled', baseTokens.agentSettled),
      agentAwaitingUser: c('agentAwaitingUser', baseTokens.agentAwaitingUser),
      agentError: c('agentError', baseTokens.agentError),
      userBubble: c('userBubble', baseTokens.userBubble),
      thinking: c('thinking', baseTokens.thinking),
      diffAddedBg: c('diffAddedBg', baseTokens.diffAddedBg),
      diffAddedFg: c('diffAddedFg', baseTokens.diffAddedFg),
      diffRemovedBg: c('diffRemovedBg', baseTokens.diffRemovedBg),
      diffRemovedFg: c('diffRemovedFg', baseTokens.diffRemovedFg),
      diffContextFg: c('diffContextFg', baseTokens.diffContextFg),
      syntaxKeyword: s('keyword', baseTokens.syntaxKeyword),
      syntaxString: s('string', baseTokens.syntaxString),
      syntaxNumber: s('number', baseTokens.syntaxNumber),
      syntaxComment: s('comment', baseTokens.syntaxComment),
      syntaxFunction: s('function', baseTokens.syntaxFunction),
      syntaxType: s('type', baseTokens.syntaxType),
      syntaxVariable: s('variable', baseTokens.syntaxVariable),
      syntaxOperator: s('operator', baseTokens.syntaxOperator),
      syntaxPunctuation: s('punctuation', baseTokens.syntaxPunctuation),
      syntaxInvalid: s('invalid', baseTokens.syntaxInvalid),
      radiusSm: rSm,
      radiusMd: rMd,
      radiusLg: rLg,
      radiusPill: rPill,
      uiFontFamily: uiFont,
      monoFontFamily: monoFont,
      headingFontFamily: rawTypography['headingFontFamily'] is String
          ? rawTypography['headingFontFamily'] as String
          : baseTokens.headingFontFamily,
      chassis: c('chassis', baseTokens.chassis),
      displaySurface: c('displaySurface', baseTokens.displaySurface),
      displayText: c('displayText', baseTokens.displayText),
      signalWarning: c('signalWarning', baseTokens.signalWarning),
      signalDanger: c('signalDanger', baseTokens.signalDanger),
      pressDuration: Duration(
        milliseconds: numVal(rawMotion['fast'], 120).clamp(0, 300).round(),
      ),
      panelDuration: Duration(
        milliseconds: numVal(rawMotion['normal'], 240).clamp(0, 300).round(),
      ),
    );
  }

  ThemeData toThemeData() {
    final tokens = toTokens();
    final isDark = variant == 'dark';

    final colorScheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: tokens.accent,
      onPrimary: tokens.accentContrast,
      secondary: tokens.accent,
      onSecondary: tokens.accentContrast,
      error: tokens.danger,
      onError: tokens.accentContrast,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
    );

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      fontFamily: tokens.uiFontFamily,
      dividerColor: tokens.border,
      cardColor: tokens.surface,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme:
          TextTheme(
                headlineLarge: TextStyle(
                  fontSize: 32,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                  letterSpacing: -0.8,
                ),
                headlineSmall: TextStyle(
                  fontSize: 24,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                  letterSpacing: -0.5,
                ),
                titleLarge: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
                titleMedium: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
                bodyLarge: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: tokens.textPrimary,
                ),
                bodyMedium: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: tokens.textPrimary,
                ),
                bodySmall: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: tokens.textSecondary,
                ),
                labelLarge: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              )
              .apply(fontFamily: tokens.uiFontFamily)
              .copyWith(
                headlineLarge: TextStyle(
                  fontFamily: tokens.headingFontFamily,
                  fontSize: 56,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                  letterSpacing: -0.5,
                ),
                headlineSmall: TextStyle(
                  fontFamily: tokens.headingFontFamily,
                  fontSize: 32,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
                titleLarge: TextStyle(
                  fontFamily: tokens.headingFontFamily,
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accent,
        selectionColor: tokens.accent.withValues(alpha: 0.2),
        selectionHandleColor: tokens.accent,
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: tokens.surface,
        scrimColor: tokens.overlay,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: tokens.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: BorderSide(color: tokens.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.textPrimary,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        textStyle: TextStyle(
          color: tokens.background,
          fontFamily: tokens.uiFontFamily,
          fontSize: 12,
        ),
        waitDuration: const Duration(milliseconds: 450),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceElevated,
        contentTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontFamily: tokens.uiFontFamily,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.borderStrong),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: tokens.accentContrast,
          elevation: 0,
          disabledBackgroundColor: tokens.surfaceElevated,
          disabledForegroundColor: tokens.textMuted,
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: tokens.accentContrast,
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          side: BorderSide(color: tokens.borderStrong),
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surface,
        surfaceTintColor: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.border),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: tokens.accent,
        unselectedLabelColor: tokens.textSecondary,
        indicatorColor: tokens.accent,
        dividerColor: tokens.border,
        labelStyle: TextStyle(
          fontFamily: tokens.uiFontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: tokens.textPrimary,
        iconColor: tokens.textSecondary,
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border, width: 1),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceElevated,
        hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: tokens.textSecondary),
        errorStyle: TextStyle(color: tokens.danger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.focusRing, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide: BorderSide(color: tokens.danger, width: 1.5),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.dragged)
              ? tokens.textSecondary
              : tokens.textMuted.withValues(alpha: 0.45),
        ),
        thickness: WidgetStateProperty.all(6),
        radius: Radius.circular(tokens.radiusSm),
      ),
      extensions: [tokens],
    );
  }
}

import 'package:flutter/material.dart';

class CrustTokens extends ThemeExtension<CrustTokens> {
  // Core colors
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color overlay;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentContrast;
  final Color focusRing;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color agentWorking;
  final Color agentRetrying;
  final Color agentCompacting;
  final Color agentSettled;
  final Color agentAwaitingUser;
  final Color agentError;
  final Color userBubble;
  final Color thinking;

  // Diff tokens
  final Color diffAddedBg;
  final Color diffAddedFg;
  final Color diffRemovedBg;
  final Color diffRemovedFg;
  final Color diffContextFg;

  // Syntax highlighting tokens
  final Color syntaxKeyword;
  final Color syntaxString;
  final Color syntaxNumber;
  final Color syntaxComment;
  final Color syntaxFunction;
  final Color syntaxType;
  final Color syntaxVariable;
  final Color syntaxOperator;
  final Color syntaxPunctuation;
  final Color syntaxInvalid;

  // Radii tokens
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusPill;

  // Typography tokens
  final String uiFontFamily;
  final String monoFontFamily;
  final String headingFontFamily;
  final Color chassis;
  final Color displaySurface;
  final Color displayText;
  final Color signalWarning;
  final Color signalDanger;
  final Duration pressDuration;
  final Duration panelDuration;
  final Curve enterCurve;
  final Curve panelCurve;

  const CrustTokens({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.overlay,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentContrast,
    required this.focusRing,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.agentWorking,
    required this.agentRetrying,
    required this.agentCompacting,
    required this.agentSettled,
    required this.agentAwaitingUser,
    required this.agentError,
    required this.userBubble,
    required this.thinking,
    required this.diffAddedBg,
    required this.diffAddedFg,
    required this.diffRemovedBg,
    required this.diffRemovedFg,
    required this.diffContextFg,
    required this.syntaxKeyword,
    required this.syntaxString,
    required this.syntaxNumber,
    required this.syntaxComment,
    required this.syntaxFunction,
    required this.syntaxType,
    required this.syntaxVariable,
    required this.syntaxOperator,
    required this.syntaxPunctuation,
    required this.syntaxInvalid,
    this.radiusSm = 2.0,
    this.radiusMd = 2.0,
    this.radiusLg = 4.0,
    this.radiusPill = 999.0,
    this.uiFontFamily = 'SchibstedGrotesk',
    this.monoFontFamily = 'SourceCodePro',
    this.headingFontFamily = 'BarlowCondensed',
    Color? chassis,
    Color? displaySurface,
    Color? displayText,
    Color? signalWarning,
    Color? signalDanger,
    this.pressDuration = const Duration(milliseconds: 120),
    this.panelDuration = const Duration(milliseconds: 240),
    this.enterCurve = const Cubic(0.23, 1, 0.32, 1),
    this.panelCurve = const Cubic(0.32, 0.72, 0, 1),
  }) : chassis = chassis ?? surfaceElevated,
       displaySurface = displaySurface ?? textPrimary,
       displayText = displayText ?? background,
       signalWarning = signalWarning ?? warning,
       signalDanger = signalDanger ?? danger;

  static const dark = CrustTokens(
    background: Color(0xFF151916),
    surface: Color(0xFF202621),
    surfaceElevated: Color(0xFF303931),
    chassis: Color(0xFF262D27),
    displaySurface: Color(0xFF080C09),
    displayText: Color(0xFFF0F2E9),
    signalWarning: Color(0xFFF1B73A),
    signalDanger: Color(0xFFE6423A),
    overlay: Color(0xB31C211E),
    border: Color(0xFF424D43),
    borderStrong: Color(0xFF657568),
    textPrimary: Color(0xFFF0F2E9),
    textSecondary: Color(0xFFCAD0C5),
    textMuted: Color(0xFFA7B2A3),
    accent: Color(0xFF83CCA1),
    accentContrast: Color(0xFF173024),
    focusRing: Color(0xFF83CCA1),
    success: Color(0xFF83CCA1),
    warning: Color(0xFFF1B73A),
    danger: Color(0xFFFF9A91),
    info: Color(0xFFB7C8D0),
    agentWorking: Color(0xFF83CCA1),
    agentRetrying: Color(0xFFF1B73A),
    agentCompacting: Color(0xFFB7C8D0),
    agentSettled: Color(0xFF83CCA1),
    agentAwaitingUser: Color(0xFFF1B73A),
    agentError: Color(0xFFFF9A91),
    userBubble: Color(0xFF303D32),
    thinking: Color(0xFFCFBBA6),
    diffAddedBg: Color(0xFF223D2C),
    diffAddedFg: Color(0xFF9BD8B2),
    diffRemovedBg: Color(0xFF462E29),
    diffRemovedFg: Color(0xFFFFB2AA),
    diffContextFg: Color(0xFFA7B2A3),
    syntaxKeyword: Color(0xFFFFB2AA),
    syntaxString: Color(0xFF9BD8B2),
    syntaxNumber: Color(0xFFF1C778),
    syntaxComment: Color(0xFFA7B2A3),
    syntaxFunction: Color(0xFFD8C5B0),
    syntaxType: Color(0xFFB7C8D0),
    syntaxVariable: Color(0xFFF0F2E9),
    syntaxOperator: Color(0xFFCAD0C5),
    syntaxPunctuation: Color(0xFFCAD0C5),
    syntaxInvalid: Color(0xFFFF9A91),
  );

  static const light = CrustTokens(
    background: Color(0xFFF8F9F5),
    surface: Color(0xFFF8F9F5),
    surfaceElevated: Color(0xFFE6E9DE),
    chassis: Color(0xFFD3D8D2),
    displaySurface: Color(0xFF191D1A),
    displayText: Color(0xFFF8F9F5),
    signalWarning: Color(0xFFF1B73A),
    signalDanger: Color(0xFFE6423A),
    overlay: Color(0x665B4A3B),
    border: Color(0xFFC3CABC),
    borderStrong: Color(0xFF818A7D),
    textPrimary: Color(0xFF191D1A),
    textSecondary: Color(0xFF5B4A3B),
    textMuted: Color(0xFF586253),
    accent: Color(0xFF0D703F),
    accentContrast: Color(0xFFF3F4EC),
    focusRing: Color(0xFF0D703F),
    success: Color(0xFF0D703F),
    warning: Color(0xFF805500),
    danger: Color(0xFFB42D26),
    info: Color(0xFF3C606A),
    agentWorking: Color(0xFF0D703F),
    agentRetrying: Color(0xFF805500),
    agentCompacting: Color(0xFF3C606A),
    agentSettled: Color(0xFF0D703F),
    agentAwaitingUser: Color(0xFF805500),
    agentError: Color(0xFFB42D26),
    userBubble: Color(0xFFE6E9DE),
    thinking: Color(0xFF5B4A3B),
    diffAddedBg: Color(0xFFDDEBDD),
    diffAddedFg: Color(0xFF0D703F),
    diffRemovedBg: Color(0xFFF3DDD5),
    diffRemovedFg: Color(0xFF9C2A24),
    diffContextFg: Color(0xFF586253),
    syntaxKeyword: Color(0xFF9C2A24),
    syntaxString: Color(0xFF0D703F),
    syntaxNumber: Color(0xFF805500),
    syntaxComment: Color(0xFF586253),
    syntaxFunction: Color(0xFF5B4A3B),
    syntaxType: Color(0xFF3C606A),
    syntaxVariable: Color(0xFF252E28),
    syntaxOperator: Color(0xFF5B4A3B),
    syntaxPunctuation: Color(0xFF586253),
    syntaxInvalid: Color(0xFFB42D26),
  );

  @override
  ThemeExtension<CrustTokens> copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? overlay,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentContrast,
    Color? focusRing,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? agentWorking,
    Color? agentRetrying,
    Color? agentCompacting,
    Color? agentSettled,
    Color? agentAwaitingUser,
    Color? agentError,
    Color? userBubble,
    Color? thinking,
    Color? diffAddedBg,
    Color? diffAddedFg,
    Color? diffRemovedBg,
    Color? diffRemovedFg,
    Color? diffContextFg,
    Color? syntaxKeyword,
    Color? syntaxString,
    Color? syntaxNumber,
    Color? syntaxComment,
    Color? syntaxFunction,
    Color? syntaxType,
    Color? syntaxVariable,
    Color? syntaxOperator,
    Color? syntaxPunctuation,
    Color? syntaxInvalid,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusPill,
    String? uiFontFamily,
    String? monoFontFamily,
    String? headingFontFamily,
    Color? chassis,
    Color? displaySurface,
    Color? displayText,
    Color? signalWarning,
    Color? signalDanger,
    Duration? pressDuration,
    Duration? panelDuration,
    Curve? enterCurve,
    Curve? panelCurve,
  }) {
    return CrustTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      overlay: overlay ?? this.overlay,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentContrast: accentContrast ?? this.accentContrast,
      focusRing: focusRing ?? this.focusRing,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      agentWorking: agentWorking ?? this.agentWorking,
      agentRetrying: agentRetrying ?? this.agentRetrying,
      agentCompacting: agentCompacting ?? this.agentCompacting,
      agentSettled: agentSettled ?? this.agentSettled,
      agentAwaitingUser: agentAwaitingUser ?? this.agentAwaitingUser,
      agentError: agentError ?? this.agentError,
      userBubble: userBubble ?? this.userBubble,
      thinking: thinking ?? this.thinking,
      diffAddedBg: diffAddedBg ?? this.diffAddedBg,
      diffAddedFg: diffAddedFg ?? this.diffAddedFg,
      diffRemovedBg: diffRemovedBg ?? this.diffRemovedBg,
      diffRemovedFg: diffRemovedFg ?? this.diffRemovedFg,
      diffContextFg: diffContextFg ?? this.diffContextFg,
      syntaxKeyword: syntaxKeyword ?? this.syntaxKeyword,
      syntaxString: syntaxString ?? this.syntaxString,
      syntaxNumber: syntaxNumber ?? this.syntaxNumber,
      syntaxComment: syntaxComment ?? this.syntaxComment,
      syntaxFunction: syntaxFunction ?? this.syntaxFunction,
      syntaxType: syntaxType ?? this.syntaxType,
      syntaxVariable: syntaxVariable ?? this.syntaxVariable,
      syntaxOperator: syntaxOperator ?? this.syntaxOperator,
      syntaxPunctuation: syntaxPunctuation ?? this.syntaxPunctuation,
      syntaxInvalid: syntaxInvalid ?? this.syntaxInvalid,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusPill: radiusPill ?? this.radiusPill,
      uiFontFamily: uiFontFamily ?? this.uiFontFamily,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
      headingFontFamily: headingFontFamily ?? this.headingFontFamily,
      chassis: chassis ?? this.chassis,
      displaySurface: displaySurface ?? this.displaySurface,
      displayText: displayText ?? this.displayText,
      signalWarning: signalWarning ?? this.signalWarning,
      signalDanger: signalDanger ?? this.signalDanger,
      pressDuration: pressDuration ?? this.pressDuration,
      panelDuration: panelDuration ?? this.panelDuration,
      enterCurve: enterCurve ?? this.enterCurve,
      panelCurve: panelCurve ?? this.panelCurve,
    );
  }

  @override
  ThemeExtension<CrustTokens> lerp(
    ThemeExtension<CrustTokens>? other,
    double t,
  ) {
    if (other is! CrustTokens) return this;
    return CrustTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContrast: Color.lerp(accentContrast, other.accentContrast, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      agentWorking: Color.lerp(agentWorking, other.agentWorking, t)!,
      agentRetrying: Color.lerp(agentRetrying, other.agentRetrying, t)!,
      agentCompacting: Color.lerp(agentCompacting, other.agentCompacting, t)!,
      agentSettled: Color.lerp(agentSettled, other.agentSettled, t)!,
      agentAwaitingUser: Color.lerp(
        agentAwaitingUser,
        other.agentAwaitingUser,
        t,
      )!,
      agentError: Color.lerp(agentError, other.agentError, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      thinking: Color.lerp(thinking, other.thinking, t)!,
      diffAddedBg: Color.lerp(diffAddedBg, other.diffAddedBg, t)!,
      diffAddedFg: Color.lerp(diffAddedFg, other.diffAddedFg, t)!,
      diffRemovedBg: Color.lerp(diffRemovedBg, other.diffRemovedBg, t)!,
      diffRemovedFg: Color.lerp(diffRemovedFg, other.diffRemovedFg, t)!,
      diffContextFg: Color.lerp(diffContextFg, other.diffContextFg, t)!,
      syntaxKeyword: Color.lerp(syntaxKeyword, other.syntaxKeyword, t)!,
      syntaxString: Color.lerp(syntaxString, other.syntaxString, t)!,
      syntaxNumber: Color.lerp(syntaxNumber, other.syntaxNumber, t)!,
      syntaxComment: Color.lerp(syntaxComment, other.syntaxComment, t)!,
      syntaxFunction: Color.lerp(syntaxFunction, other.syntaxFunction, t)!,
      syntaxType: Color.lerp(syntaxType, other.syntaxType, t)!,
      syntaxVariable: Color.lerp(syntaxVariable, other.syntaxVariable, t)!,
      syntaxOperator: Color.lerp(syntaxOperator, other.syntaxOperator, t)!,
      syntaxPunctuation: Color.lerp(
        syntaxPunctuation,
        other.syntaxPunctuation,
        t,
      )!,
      syntaxInvalid: Color.lerp(syntaxInvalid, other.syntaxInvalid, t)!,
      radiusSm: (radiusSm + (other.radiusSm - radiusSm) * t),
      radiusMd: (radiusMd + (other.radiusMd - radiusMd) * t),
      radiusLg: (radiusLg + (other.radiusLg - radiusLg) * t),
      radiusPill: (radiusPill + (other.radiusPill - radiusPill) * t),
      uiFontFamily: t < 0.5 ? uiFontFamily : other.uiFontFamily,
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
      headingFontFamily: t < 0.5 ? headingFontFamily : other.headingFontFamily,
      chassis: Color.lerp(chassis, other.chassis, t)!,
      displaySurface: Color.lerp(displaySurface, other.displaySurface, t)!,
      displayText: Color.lerp(displayText, other.displayText, t)!,
      signalWarning: Color.lerp(signalWarning, other.signalWarning, t)!,
      signalDanger: Color.lerp(signalDanger, other.signalDanger, t)!,
      pressDuration: t < 0.5 ? pressDuration : other.pressDuration,
      panelDuration: t < 0.5 ? panelDuration : other.panelDuration,
      enterCurve: t < 0.5 ? enterCurve : other.enterCurve,
      panelCurve: t < 0.5 ? panelCurve : other.panelCurve,
    );
  }
}

extension CrustTokensExtension on BuildContext {
  CrustTokens get tokens =>
      Theme.of(this).extension<CrustTokens>() ?? CrustTokens.dark;
}

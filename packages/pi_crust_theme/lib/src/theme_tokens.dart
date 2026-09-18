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
    this.radiusSm = 6.0,
    this.radiusMd = 10.0,
    this.radiusLg = 16.0,
    this.radiusPill = 999.0,
    this.uiFontFamily = 'Inter',
    this.monoFontFamily = 'JetBrains Mono',
  });

  static const dark = CrustTokens(
    background: Color(0xFF0E1116),
    surface: Color(0xFF141922),
    surfaceElevated: Color(0xFF1B2230),
    overlay: Color(0xCC0A0D12),
    border: Color(0xFF242C3A),
    borderStrong: Color(0x80334054),
    textPrimary: Color(0xFFE6EAF2),
    textSecondary: Color(0xFF9AA6B8),
    textMuted: Color(0xFF66738A),
    accent: Color(0xFF7C9CFF),
    accentContrast: Color(0xFF0B0F16),
    focusRing: Color(0xFF7C9CFF),
    success: Color(0xFF4ED08A),
    warning: Color(0xFFE8B341),
    danger: Color(0xFFF1687A),
    info: Color(0xFF59B9E8),
    agentWorking: Color(0xFF7C9CFF),
    agentRetrying: Color(0xFFE8B341),
    agentCompacting: Color(0xFF59B9E8),
    agentSettled: Color(0xFF4ED08A),
    agentAwaitingUser: Color(0xFFC08CFF),
    agentError: Color(0xFFF1687A),
    userBubble: Color(0xFF18202C),
    thinking: Color(0xFF8E7BD6),
    diffAddedBg: Color(0xFF10301F),
    diffAddedFg: Color(0xFF7EE0A8),
    diffRemovedBg: Color(0xFF3A1620),
    diffRemovedFg: Color(0xFFF59AA8),
    diffContextFg: Color(0xFF8592A6),
    syntaxKeyword: Color(0xFFC792EA),
    syntaxString: Color(0xFF9CE29C),
    syntaxNumber: Color(0xFFF2A65A),
    syntaxComment: Color(0xFF5C6A80),
    syntaxFunction: Color(0xFF7C9CFF),
    syntaxType: Color(0xFF59D3C0),
    syntaxVariable: Color(0xFFE6EAF2),
    syntaxOperator: Color(0xFF9AA6B8),
    syntaxPunctuation: Color(0xFF7E8AA0),
    syntaxInvalid: Color(0xFFF1687A),
    radiusSm: 6.0,
    radiusMd: 10.0,
    radiusLg: 16.0,
    radiusPill: 999.0,
    uiFontFamily: 'Inter',
    monoFontFamily: 'JetBrains Mono',
  );

  static const light = CrustTokens(
    background: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF0F3F6),
    overlay: Color(0x330A0D12),
    border: Color(0xFFD0D7DE),
    borderStrong: Color(0x808C959F),
    textPrimary: Color(0xFF1F2328),
    textSecondary: Color(0xFF57606A),
    textMuted: Color(0xFF8C959F),
    accent: Color(0xFF0969DA),
    accentContrast: Color(0xFFFFFFFF),
    focusRing: Color(0xFF0969DA),
    success: Color(0xFF1A7F37),
    warning: Color(0xFF9A6700),
    danger: Color(0xFFCF222E),
    info: Color(0xFF0969DA),
    agentWorking: Color(0xFF0969DA),
    agentRetrying: Color(0xFF9A6700),
    agentCompacting: Color(0xFF0969DA),
    agentSettled: Color(0xFF1A7F37),
    agentAwaitingUser: Color(0xFF8250DF),
    agentError: Color(0xFFCF222E),
    userBubble: Color(0xFFEAEFF5),
    thinking: Color(0xFF6639BA),
    diffAddedBg: Color(0xFFE6FFEC),
    diffAddedFg: Color(0xFF1A7F37),
    diffRemovedBg: Color(0xFFFFEBE9),
    diffRemovedFg: Color(0xFFCF222E),
    diffContextFg: Color(0xFF57606A),
    syntaxKeyword: Color(0xFFCF222E),
    syntaxString: Color(0xFF0A3069),
    syntaxNumber: Color(0xFF953800),
    syntaxComment: Color(0xFF6E7781),
    syntaxFunction: Color(0xFF8250DF),
    syntaxType: Color(0xFF0550AE),
    syntaxVariable: Color(0xFF1F2328),
    syntaxOperator: Color(0xFF57606A),
    syntaxPunctuation: Color(0xFF57606A),
    syntaxInvalid: Color(0xFFCF222E),
    radiusSm: 6.0,
    radiusMd: 10.0,
    radiusLg: 16.0,
    radiusPill: 999.0,
    uiFontFamily: 'Inter',
    monoFontFamily: 'JetBrains Mono',
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
    );
  }

  @override
  ThemeExtension<CrustTokens> lerp(
      ThemeExtension<CrustTokens>? other, double t) {
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
      agentAwaitingUser:
          Color.lerp(agentAwaitingUser, other.agentAwaitingUser, t)!,
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
      syntaxPunctuation:
          Color.lerp(syntaxPunctuation, other.syntaxPunctuation, t)!,
      syntaxInvalid: Color.lerp(syntaxInvalid, other.syntaxInvalid, t)!,
      radiusSm: (radiusSm + (other.radiusSm - radiusSm) * t),
      radiusMd: (radiusMd + (other.radiusMd - radiusMd) * t),
      radiusLg: (radiusLg + (other.radiusLg - radiusLg) * t),
      radiusPill: (radiusPill + (other.radiusPill - radiusPill) * t),
      uiFontFamily: t < 0.5 ? uiFontFamily : other.uiFontFamily,
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
    );
  }
}

extension CrustTokensExtension on BuildContext {
  CrustTokens get tokens =>
      Theme.of(this).extension<CrustTokens>() ?? CrustTokens.dark;
}

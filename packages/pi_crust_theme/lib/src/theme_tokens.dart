import 'package:flutter/material.dart';

class CrustTokens extends ThemeExtension<CrustTokens> {
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
    );
  }

  @override
  ThemeExtension<CrustTokens> lerp(ThemeExtension<CrustTokens>? other, double t) {
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
      agentAwaitingUser: Color.lerp(agentAwaitingUser, other.agentAwaitingUser, t)!,
      agentError: Color.lerp(agentError, other.agentError, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      thinking: Color.lerp(thinking, other.thinking, t)!,
    );
  }
}

extension CrustTokensExtension on BuildContext {
  CrustTokens get tokens =>
      Theme.of(this).extension<CrustTokens>() ?? CrustTokens.dark;
}

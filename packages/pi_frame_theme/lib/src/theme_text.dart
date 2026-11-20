import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Named text roles built from the active theme's font families.
///
/// Read with `FrameText.of(context).label`. UI roles use `uiFontFamily`
/// (Schibsted Grotesk), mono roles use `monoFontFamily` (Source Code Pro).
/// Barlow Condensed (`headingFontFamily`) is brand and pane headings only and
/// is deliberately not used here. Sizes are in logical pixels; the smallest
/// role is 11 px. Colour is not set: callers apply it with `copyWith`.
class FrameText extends ThemeExtension<FrameText> {
  /// 11/16, metadata and captions.
  final TextStyle caption;

  /// 12/16 medium, labels and chips.
  final TextStyle label;

  /// 13/20, dense body text.
  final TextStyle body;

  /// 14/20, default body text.
  final TextStyle bodyLarge;

  /// 16/22 semibold, section titles.
  final TextStyle title;

  /// 20/26 semibold, dialog and page headings.
  final TextStyle heading;

  /// 28/32 semibold, display text.
  final TextStyle display;

  /// 12/18 mono, paths and short code.
  final TextStyle mono;

  /// 13/20 mono, code and diff bodies.
  final TextStyle monoBody;

  const FrameText({
    required this.caption,
    required this.label,
    required this.body,
    required this.bodyLarge,
    required this.title,
    required this.heading,
    required this.display,
    required this.mono,
    required this.monoBody,
  });

  factory FrameText.fromTokens(FrameTokens tokens) {
    final ui = tokens.uiFontFamily;
    final code = tokens.monoFontFamily;
    return FrameText(
      caption: _style(ui, 11, 16),
      label: _style(ui, 12, 16, weight: FontWeight.w500),
      body: _style(ui, 13, 20),
      bodyLarge: _style(ui, 14, 20),
      title: _style(ui, 16, 22, weight: FontWeight.w600),
      heading: _style(ui, 20, 26, weight: FontWeight.w600),
      display: _style(ui, 28, 32, weight: FontWeight.w600),
      mono: _style(code, 12, 18),
      monoBody: _style(code, 13, 20),
    );
  }

  /// The roles for the theme of [context]. Falls back to the dark defaults
  /// when the theme does not register a `FrameText` extension.
  static FrameText of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FrameText>() ??
        FrameText.fromTokens(theme.extension<FrameTokens>() ?? FrameTokens.dark);
  }

  static TextStyle _style(
    String family,
    double size,
    double lineHeight, {
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
    );
  }

  @override
  FrameText copyWith({
    TextStyle? caption,
    TextStyle? label,
    TextStyle? body,
    TextStyle? bodyLarge,
    TextStyle? title,
    TextStyle? heading,
    TextStyle? display,
    TextStyle? mono,
    TextStyle? monoBody,
  }) {
    return FrameText(
      caption: caption ?? this.caption,
      label: label ?? this.label,
      body: body ?? this.body,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      title: title ?? this.title,
      heading: heading ?? this.heading,
      display: display ?? this.display,
      mono: mono ?? this.mono,
      monoBody: monoBody ?? this.monoBody,
    );
  }

  @override
  FrameText lerp(ThemeExtension<FrameText>? other, double t) {
    if (other is! FrameText) return this;
    return FrameText(
      caption: TextStyle.lerp(caption, other.caption, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      heading: TextStyle.lerp(heading, other.heading, t)!,
      display: TextStyle.lerp(display, other.display, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoBody: TextStyle.lerp(monoBody, other.monoBody, t)!,
    );
  }
}

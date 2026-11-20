import 'package:flutter/material.dart';

import 'motion.dart';

/// Indeterminate "working" spinner for the composer, transcript and tool
/// timeline. Under reduced motion (`FrameMotion.reduced`) it is a static
/// `Icons.sync_outlined` glyph in the same square, so nothing loops on screen.
class FrameActivityIndicator extends StatelessWidget {
  /// Width and height of the square the indicator occupies.
  final double size;
  final double strokeWidth;

  /// Fixed progress for tests or a known value; null keeps it indeterminate.
  final double? value;
  final Color color;

  /// Accessible label. Also applied to the static glyph.
  final String? semanticLabel;

  const FrameActivityIndicator({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2,
    this.value,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (FrameMotion.reduced(context)) {
      return Semantics(
        label: semanticLabel,
        child: SizedBox(
          width: size,
          height: size,
          child: ExcludeSemantics(
            child: Icon(Icons.sync_outlined, size: size, color: color),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        value: value,
        color: color,
        semanticsLabel: semanticLabel,
      ),
    );
  }
}

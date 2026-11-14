import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// The meaning of a [FrameStatusTag], mapped to a semantic colour token.
enum FrameStatusTone { neutral, info, success, warning, danger }

/// A small status marker: a coloured dot followed by a [label].
///
/// The tag takes the width of its content when its parent gives it loose
/// constraints (a Row, a Wrap, a default-aligned Column). A parent that forces
/// a tight width, such as a stretched Column, gives it that width. It has no
/// background or border, so it stays flat.
class FrameStatusTag extends StatelessWidget {
  final String label;
  final FrameStatusTone tone;

  const FrameStatusTag({
    super.key,
    required this.label,
    this.tone = FrameStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final dotColor = switch (tone) {
      FrameStatusTone.neutral => tokens.textMuted,
      FrameStatusTone.info => tokens.info,
      FrameStatusTone.success => tokens.success,
      FrameStatusTone.warning => tokens.warning,
      FrameStatusTone.danger => tokens.danger,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FrameSpace.x2,
        vertical: FrameSpace.x1 / 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dot: 6 px is a glyph size, not on the spacing scale.
          DecoratedBox(
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            child: const SizedBox(width: 6, height: 6),
          ),
          const SizedBox(width: FrameSpace.x2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FrameText.of(context).caption
                  .copyWith(color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

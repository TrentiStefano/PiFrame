import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Loading state of the Git list: three skeleton rows, one row high each, and
/// a short label. The rows have the same height as the real file rows.
class GitLoadingRows extends StatelessWidget {
  const GitLoadingRows({super.key, required this.label});

  final String label;

  /// Bar widths of the three placeholder rows, as fractions of the row.
  static const _nameFractions = [0.55, 0.7, 0.4];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final fraction in _nameFractions)
          Container(
            height: FrameSize.rowList,
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: const SizedBox.square(dimension: FrameSize.icon),
                ),
                const SizedBox(width: FrameSpace.x2),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                      child: const SizedBox(height: FrameSpace.x2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: FrameSpace.x2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: text.caption.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

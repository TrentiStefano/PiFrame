import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// The "review file changes" control in the composer (plan 4.4).
///
/// With changes it reads "Rivedi modifiche (n)" when [showLabel] is set, and is an icon otherwise.
/// With no changes it stays visible but disabled, and its tooltip says when it turns on. A null
/// [onPressed] disables it.
class ComposerReviewButton extends StatelessWidget {
  const ComposerReviewButton({
    super.key,
    required this.label,
    required this.showLabel,
    required this.reviewing,
    required this.enabledTooltip,
    required this.disabledTooltip,
    required this.onPressed,
  });

  final String label;
  final bool showLabel;
  final bool reviewing;
  final String enabledTooltip;
  final String disabledTooltip;
  final VoidCallback? onPressed;

  static const double _height = FrameSize.hitMin;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final enabled = onPressed != null;
    final color = !enabled
        ? tokens.textMuted
        : reviewing
        ? tokens.accent
        : tokens.textSecondary;

    final icon = Icon(
      reviewing ? Icons.rate_review_outlined : Icons.rate_review_outlined,
      size: FrameSize.icon,
      color: color,
    );

    return Tooltip(
      message: enabled ? enabledTooltip : disabledTooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: TextButton(
          key: const ValueKey('review-changes-btn'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: color,
            backgroundColor: reviewing
                ? tokens.accent.withValues(alpha: 0.15)
                : null,
            minimumSize: const Size(0, _height),
            fixedSize: showLabel ? null : const Size(_height, _height),
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? FrameSpace.x2 : 0,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              side: BorderSide(
                color: reviewing ? tokens.accent : tokens.border,
              ),
            ),
          ),
          child: showLabel
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: FrameSpace.x1),
                    Text(
                      label,
                      maxLines: 1,
                      style: text.label.copyWith(color: color),
                    ),
                  ],
                )
              : icon,
        ),
      ),
    );
  }
}

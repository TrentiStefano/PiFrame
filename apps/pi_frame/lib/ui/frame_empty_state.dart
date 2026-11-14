import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Centered empty-state block: an [icon], a [title], one [message] sentence,
/// exactly one [actionLabel] button and an optional [shortcutHint].
///
/// The action button is the only button in the widget. It is disabled when
/// [onAction] is null. Keys: `<keyPrefix>` on the root and
/// `<keyPrefix>-action` on the button.
class FrameEmptyState extends StatelessWidget {
  final String keyPrefix;
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Keyboard shortcut shown under the button, for example "Ctrl+N".
  final String? shortcutHint;

  const FrameEmptyState({
    super.key,
    required this.keyPrefix,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.shortcutHint,
  });

  /// Icon size for the empty-state glyph. Larger than [FrameSize.iconLg]
  /// because it is an illustration, not a control icon.
  static const double _glyphSize = 32;

  /// Widest the text column may grow before it wraps.
  static const double _maxTextWidth = 320;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FrameSpace.x6),
        child: Column(
          key: ValueKey(keyPrefix),
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: _glyphSize, color: tokens.textMuted),
            ),
            const SizedBox(height: FrameSpace.x3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxTextWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.title.copyWith(color: tokens.textPrimary),
                    ),
                  ),
                  const SizedBox(height: FrameSpace.x1),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: text.body.copyWith(color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FrameSpace.x4),
            if (actionIcon == null)
              FilledButton(
                key: ValueKey('$keyPrefix-action'),
                onPressed: onAction,
                child: Text(actionLabel),
              )
            else
              FilledButton.icon(
                key: ValueKey('$keyPrefix-action'),
                onPressed: onAction,
                icon: Icon(actionIcon, size: FrameSize.icon),
                label: Text(actionLabel),
              ),
            if (shortcutHint != null) ...[
              const SizedBox(height: FrameSpace.x2),
              Text(
                shortcutHint!,
                key: ValueKey('$keyPrefix-shortcut'),
                style: text.mono.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

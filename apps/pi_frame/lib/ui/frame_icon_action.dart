import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// A 16 px icon button inside a 28 x 28 target.
///
/// [tooltip] is required: it is the accessible name as well as the hover
/// label. [shortcut], when given, is appended to the tooltip and the semantic
/// label: `Aggiorna (Ctrl+R)`. The button is focusable by keyboard, and its
/// hover, pressed and focus states come from Material. Passing a null
/// [onPressed] disables it.
class FrameIconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? shortcut;
  final bool selected;

  const FrameIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.shortcut,
    this.selected = false,
  });

  /// The tooltip text, with the shortcut in parentheses when there is one.
  String get message => shortcut == null ? tooltip : '$tooltip ($shortcut)';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPressed != null;
    final color = !enabled
        ? tokens.textMuted
        : selected
        ? tokens.accent
        : tokens.textSecondary;

    // TODO(focus-ring): wrap in FrameFocusRing once lib/ui/frame_focus.dart
    // exists. Until then the Material focus highlight below is the indicator.
    return Semantics(
      label: message,
      child: IconButton(
        onPressed: onPressed,
        tooltip: message,
        icon: Icon(icon, size: FrameSize.icon, color: color),
        isSelected: selected,
        iconSize: FrameSize.icon,
        splashRadius: FrameSize.hitMin / 2,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(FrameSize.hitMin),
          minimumSize: const Size.square(FrameSize.hitMin),
          padding: EdgeInsets.zero,
          // Keep the 28 px target: the default padded tap target would
          // enlarge it to 48 px.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        hoverColor: tokens.surfaceElevated,
        highlightColor: tokens.surfaceElevated,
        focusColor: tokens.surfaceElevated,
      ),
    );
  }
}

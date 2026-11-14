import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'frame_middle_ellipsis.dart';

/// A compact list row: optional leading icon, [name] in primary text, an
/// optional [secondary] line (a path, truncated in the middle), an optional
/// [trailing] badge, and [actions].
///
/// Height is at least `FrameSize.rowList` and grows with text scale.
/// [actions] are always in the tree and stay focusable with Tab. They are
/// visible on hover or while focus is inside the row, and otherwise only
/// their opacity changes, so the row does not shift.
///
/// [onTap] runs on click, Enter or Space when the row has focus. [onSecondaryTap]
/// receives the global pointer position, for a context menu. A null [onTap]
/// makes the row non-interactive.
class FrameListRow extends StatefulWidget {
  final String name;
  final String? secondary;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> actions;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTap;

  const FrameListRow({
    super.key,
    required this.name,
    this.secondary,
    this.leading,
    this.trailing,
    this.actions = const [],
    this.selected = false,
    this.onTap,
    this.onSecondaryTap,
  });

  @override
  State<FrameListRow> createState() => _FrameListRowState();
}

class _FrameListRowState extends State<FrameListRow> {
  bool _hovered = false;
  bool _focusWithin = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final enabled = widget.onTap != null;
    final revealActions = _hovered || _focusWithin;
    final transparent = tokens.surface.withValues(alpha: 0);
    final background = widget.selected
        ? tokens.surfaceElevated
        : _hovered
        ? tokens.surface
        : transparent;

    return Focus(
      // Only observes focus: the row's InkWell takes focus, actions inside it do too.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus != _focusWithin) setState(() => _focusWithin = hasFocus);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          selected: widget.selected,
          child: InkWell(
            // TODO(focus-ring): wrap in FrameFocusRing once lib/ui/frame_focus.dart
            // exists. Until then the Material focus highlight is the indicator.
            onTap: widget.onTap,
            onSecondaryTapUp: widget.onSecondaryTap == null
                ? null
                : (details) => widget.onSecondaryTap!(details.globalPosition),
            highlightColor: tokens.surfaceElevated,
            hoverColor: transparent,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: FrameSize.rowList),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FrameSpace.x2,
                  vertical: FrameSpace.x1,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      SizedBox(width: FrameSize.icon, child: widget.leading),
                      const SizedBox(width: FrameSpace.x2),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.body.copyWith(
                              color: enabled
                                  ? tokens.textPrimary
                                  : tokens.textMuted,
                            ),
                          ),
                          if (widget.secondary != null)
                            FrameMiddleEllipsis(
                              text: widget.secondary!,
                              style: text.caption.copyWith(
                                color: tokens.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: FrameSpace.x2),
                      widget.trailing!,
                    ],
                    if (widget.actions.isNotEmpty) ...[
                      const SizedBox(width: FrameSpace.x1),
                      Opacity(
                        opacity: revealActions ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !revealActions,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: widget.actions,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

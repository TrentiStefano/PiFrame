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
///
/// [inlineSecondary] puts [secondary] on the same line as [name], after it, so
/// a row can stay one line high. The name keeps its full width and only the
/// secondary text is shortened. [focusable] false takes the row out of the Tab
/// order, for lists that handle arrow keys themselves. With
/// [revealActionsWhenSelected] the actions also show on the selected row, so a
/// keyboard cursor shows them too. [revealActionsAlways] keeps them visible
/// all the time, for layouts without a hover pointer (touch, compact).
class FrameListRow extends StatefulWidget {
  final String name;
  final String? secondary;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> actions;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final bool inlineSecondary;
  final bool focusable;
  final bool revealActionsWhenSelected;
  final bool revealActionsAlways;

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
    this.inlineSecondary = false,
    this.focusable = true,
    this.revealActionsWhenSelected = false,
    this.revealActionsAlways = false,
  });

  @override
  State<FrameListRow> createState() => _FrameListRowState();
}

class _FrameListRowState extends State<FrameListRow> {
  bool _hovered = false;
  bool _focusWithin = false;

  /// Name first, at its full width when the row allows it, then the secondary
  /// text in what is left. The name is only cut when it does not fit alone.
  ///
  /// The name is capped by a [ConstrainedBox] at the row width minus the gap,
  /// so layout, not a text measurement, decides its width. The secondary is
  /// an [Expanded] and gets whatever the name leaves.
  Widget _inlineTitle(FrameText text, FrameTokens tokens, bool enabled) {
    final secondary = widget.secondary;
    final gap = secondary == null ? 0.0 : FrameSpace.x2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = constraints.maxWidth - gap;
        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cap < 0 ? 0 : cap),
              child: Text(
                widget.name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: text.body.copyWith(
                  color: enabled ? tokens.textPrimary : tokens.textMuted,
                ),
              ),
            ),
            if (secondary != null) ...[
              const SizedBox(width: FrameSpace.x2),
              Expanded(
                child: FrameMiddleEllipsis(
                  text: secondary,
                  style: text.caption.copyWith(color: tokens.textMuted),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final enabled = widget.onTap != null;
    final revealActions =
        widget.revealActionsAlways ||
        _hovered ||
        _focusWithin ||
        (widget.revealActionsWhenSelected && widget.selected);
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
            canRequestFocus: widget.focusable,
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
                // No vertical padding: the 28 px minimum height and the
                // 28 px action targets set the row height.
                padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
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
                      child: widget.inlineSecondary
                          ? _inlineTitle(text, tokens, enabled)
                          : Column(
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

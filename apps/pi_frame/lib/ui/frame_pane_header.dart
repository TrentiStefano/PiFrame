import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'frame_middle_ellipsis.dart';

/// The heading of a pane: a [title] in the pane-heading style (Barlow
/// Condensed, FrameTokens.headingFontFamily, the only place it is used), an
/// optional [subtitle] such as a path (mono, truncated in the middle),
/// trailing [actions] and an optional [tabs] strip below.
///
/// [titleWidget] replaces the [title] text when given, for a title that has
/// its own gestures or controls (such as a double-tap rename). [title] is
/// still required, so the pane keeps a plain-text label without it.
///
/// With [actionsOnOwnLine] the actions move to their own line under the
/// title and subtitle, for a pane too narrow to fit both: the title keeps the
/// full width and every action stays visible.
///
/// The header row is at least FrameSize.paneHeader tall. It is flat, with
/// no card or elevation. It has no interactive state of its own: the actions
/// carry their own focus, hover and disabled states.
class FramePaneHeader extends StatelessWidget {
  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final List<Widget> actions;
  final Widget? tabs;
  final bool actionsOnOwnLine;

  const FramePaneHeader({
    super.key,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.actions = const [],
    this.tabs,
    this.actionsOnOwnLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final titleStyle = text.heading.copyWith(
      fontFamily: tokens.headingFontFamily,
      color: tokens.textPrimary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FrameSize.paneHeader),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FrameSpace.x3,
              vertical: 4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child:
                            titleWidget ??
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                      ),
                    ),
                    if (!actionsOnOwnLine)
                      for (final action in actions) ...[
                        const SizedBox(width: FrameSpace.x1),
                        action,
                      ],
                  ],
                ),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 2),
                  subtitleWidget!,
                ] else if (subtitle != null) ...[
                  FrameMiddleEllipsis(
                    text: subtitle!,
                    style: text.mono.copyWith(color: tokens.textMuted),
                  ),
                ],
                if (actionsOnOwnLine && actions.isNotEmpty) ...[
                  const SizedBox(height: FrameSpace.x1),
                  Row(
                    key: const ValueKey('pane-header-actions-line'),
                    children: [
                      for (final (i, action) in actions.indexed) ...[
                        if (i > 0) const SizedBox(width: FrameSpace.x1),
                        Flexible(child: action),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        ?tabs,
      ],
    );
  }
}

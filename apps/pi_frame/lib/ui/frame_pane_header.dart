import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'frame_middle_ellipsis.dart';

/// The heading of a pane: a [title] in the pane-heading style (Barlow
/// Condensed, `FrameTokens.headingFontFamily`, the only place it is used), an
/// optional [subtitle] such as a path (mono, truncated in the middle),
/// trailing [actions] and an optional [tabs] strip below.
///
/// The header row is at least `FrameSize.paneHeader` tall. It is flat, with
/// no card or elevation. It has no interactive state of its own: the actions
/// carry their own focus, hover and disabled states.
class FramePaneHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? tabs;

  const FramePaneHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.tabs,
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
            padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      if (subtitle != null)
                        FrameMiddleEllipsis(
                          text: subtitle!,
                          style: text.mono.copyWith(color: tokens.textMuted),
                        ),
                    ],
                  ),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: FrameSpace.x1),
                  action,
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

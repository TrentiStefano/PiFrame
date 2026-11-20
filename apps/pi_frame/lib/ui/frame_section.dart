import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// A settings or dialog section: a [title], an optional [description] and
/// the section's [child] content, inside one border level.
///
/// The title uses the `title` text role (Schibsted Grotesk, not the Barlow
/// pane-heading face). Padding is `FrameSpace.x4` on every side.
class FrameSection extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;

  const FrameSection({
    super.key,
    required this.title,
    this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    return Container(
      padding: const EdgeInsets.all(FrameSpace.x4),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: text.title.copyWith(color: tokens.textPrimary),
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: FrameSpace.x1),
            Text(
              description!,
              style: text.body.copyWith(color: tokens.textSecondary),
            ),
          ],
          const SizedBox(height: FrameSpace.x3),
          child,
        ],
      ),
    );
  }
}

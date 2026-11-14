import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Collapsible section title ("Staged", "Changes") used by the Git pane list.
/// One row high, like the file rows under it.
class GitSectionHeader extends StatelessWidget {
  const GitSectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
    this.trailing,
  });

  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    return InkWell(
      onTap: onToggle,
      hoverColor: tokens.accent.withValues(alpha: 0.05),
      child: Container(
        height: FrameSize.rowList,
        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated.withValues(alpha: 0.6),
          border: Border(
            top: BorderSide(color: tokens.borderStrong, width: 0.5),
            bottom: BorderSide(color: tokens.borderStrong, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: FrameSize.icon,
              color: tokens.textMuted,
            ),
            const SizedBox(width: FrameSpace.x2),
            Text(
              title.toUpperCase(),
              style: text.caption.copyWith(
                color: tokens.displayText,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: FrameSpace.x2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x1),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                '$count',
                style: text.caption.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

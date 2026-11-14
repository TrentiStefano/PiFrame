import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Collapsible section title ("Staged", "Changes") used by the Git pane list.
class GitSectionHeader extends StatelessWidget {
  const GitSectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
    required this.tokens,
    this.trailing,
  });

  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;
  final FrameTokens tokens;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      hoverColor: tokens.accent.withValues(alpha: 0.05),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
              size: 16,
              color: tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: tokens.displayText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 10,
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

import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';

/// How long the Packages list may load before the "taking longer" notice shows.
const packageLoadSlowThreshold = Duration(seconds: 10);

const _skeletonRowCount = 4;

/// Loading state for the Packages tab: a labelled, static skeleton.
///
/// Static on purpose: there is no shimmer loop, so nothing animates under
/// reduced motion. Once [slow] is true the timeout notice and a retry action
/// appear below the skeleton, which stays visible.
class PackageLoadingView extends StatelessWidget {
  final FrameTokens tokens;
  final AppStrings strings;
  final bool slow;
  final VoidCallback onRetry;

  const PackageLoadingView({
    super.key,
    required this.tokens,
    required this.strings,
    required this.slow,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final text = FrameText.of(context);
    return ListView(
      key: const ValueKey('packages-loading'),
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        Row(
          children: [
            Icon(
              Icons.hourglass_empty,
              color: tokens.textMuted,
              size: FrameSize.icon,
            ),
            const SizedBox(width: FrameSpace.x2),
            Text(
              strings.packagesLoading,
              key: const ValueKey('packages-loading-label'),
              style: text.body.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
        const SizedBox(height: FrameSpace.x4),
        for (var i = 0; i < _skeletonRowCount; i++) const _SkeletonRow(),
        if (slow) ...[
          const SizedBox(height: FrameSpace.x2),
          Text(
            strings.packagesLoadingSlow,
            key: const ValueKey('packages-loading-slow'),
            style: text.body.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: FrameSpace.x2),
          OutlinedButton.icon(
            key: const ValueKey('packages-load-retry'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, FrameSize.rowForm),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: FrameSize.icon),
            label: Text(strings.retryAction),
          ),
        ],
      ],
    );
  }
}

/// One placeholder row: two bars, no border, same rhythm as a list row.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.border,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
    );
    return Padding(
      key: const ValueKey('packages-skeleton-row'),
      padding: const EdgeInsets.symmetric(vertical: FrameSpace.x2),
      child: SizedBox(
        height: FrameSize.rowList,
        child: Row(
          children: [
            bar(FrameSize.icon, FrameSize.icon),
            const SizedBox(width: FrameSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  bar(180, 12),
                  const SizedBox(height: FrameSpace.x1 + 2),
                  bar(260, 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

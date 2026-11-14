import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../ui/motion.dart';

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
    return ListView(
      key: const ValueKey('packages-loading'),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(Icons.hourglass_empty, color: tokens.textMuted, size: 16),
            const SizedBox(width: 8),
            Text(
              strings.packagesLoading,
              key: const ValueKey('packages-loading-label'),
              style: TextStyle(color: tokens.textMuted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _skeletonRowCount; i++) const _SkeletonRow(),
        if (slow) ...[
          const SizedBox(height: 8),
          Text(
            strings.packagesLoadingSlow,
            key: const ValueKey('packages-loading-slow'),
            style: TextStyle(color: tokens.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('packages-load-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(strings.retryAction),
          ),
        ],
      ],
    );
  }
}

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
    return Container(
      key: const ValueKey('packages-skeleton-row'),
      margin: const EdgeInsets.only(bottom: 8),
      height: 56,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          bar(18, 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                bar(180, 12),
                const SizedBox(height: 6),
                bar(260, 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state for the Packages tab: a small, self-contained callout.
///
/// [details] is the raw error text, shown inside a collapsible "Dettagli"
/// section. Task 1.6 can replace the title and details with a mapped
/// user-facing error without changing this layout.
class PackageLoadErrorCallout extends StatefulWidget {
  final FrameTokens tokens;
  final AppStrings strings;
  final String title;
  final String details;
  final VoidCallback onRetry;

  const PackageLoadErrorCallout({
    super.key,
    required this.tokens,
    required this.strings,
    required this.title,
    required this.details,
    required this.onRetry,
  });

  @override
  State<PackageLoadErrorCallout> createState() =>
      _PackageLoadErrorCalloutState();
}

class _PackageLoadErrorCalloutState extends State<PackageLoadErrorCallout> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final strings = widget.strings;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        key: const ValueKey('packages-load-error'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.danger),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: tokens.danger, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    key: const ValueKey('packages-load-error-title'),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('packages-load-retry'),
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(strings.retryAction),
                ),
                TextButton.icon(
                  key: const ValueKey('packages-load-details-toggle'),
                  onPressed: () =>
                      setState(() => _showDetails = !_showDetails),
                  icon: Icon(
                    _showDetails ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(strings.detailsAction),
                ),
              ],
            ),
            FrameExpandable(
              expanded: _showDetails,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  widget.details,
                  key: const ValueKey('packages-load-details'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

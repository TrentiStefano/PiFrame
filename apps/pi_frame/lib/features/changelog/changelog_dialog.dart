import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/platform/link_service.dart';
import '../../domain/changelog/changelog_models.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/precision.dart';

/// Popup dialog presenting release highlights (features and bug fixes only)
/// to the user after an update.
class ChangelogDialog extends ConsumerWidget {
  final ChangelogRelease release;

  const ChangelogDialog({super.key, required this.release});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final links = ref.read(linkServiceProvider);

    return FrameDialog<void>(
      title: strings.changelogTitle(release.version),
      maxWidth: 580,
      headerActions: [
        if (release.date != null && release.date!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: FrameSpace.x2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(release.date!, style: text.caption.copyWith(color: tokens.textMuted)),
            ),
          ),
      ],
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.changelogSubtitle, style: text.label.copyWith(color: tokens.textSecondary)),
            const SizedBox(height: FrameSpace.x4),

            // Features section
            if (release.features.isNotEmpty) ...[
              _buildSectionHeader(
                context: context,
                tokens: tokens,
                icon: Icons.auto_awesome_rounded,
                title: strings.changelogFeaturesTitle,
                color: tokens.accent,
                count: release.features.length,
              ),
              const SizedBox(height: FrameSpace.x2),
              ...release.features.map(
                (item) => _buildItemRow(
                  context: context,
                  links: links,
                  tokens: tokens,
                  item: item,
                  accentColor: tokens.accent,
                ),
              ),
              const SizedBox(height: FrameSpace.x4),
            ],

            // Bug Fixes section
            if (release.fixes.isNotEmpty) ...[
              _buildSectionHeader(
                context: context,
                tokens: tokens,
                icon: Icons.bug_report_outlined,
                title: strings.changelogFixesTitle,
                color: tokens.textPrimary,
                count: release.fixes.length,
              ),
              const SizedBox(height: FrameSpace.x2),
              ...release.fixes.map(
                (item) => _buildItemRow(
                  context: context,
                  links: links,
                  tokens: tokens,
                  item: item,
                  accentColor: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: FrameSpace.x4),
            ],

            // Empty state
            if (release.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: FrameSpace.x4),
                child: Text(strings.changelogNoChanges, style: text.body.copyWith(color: tokens.textSecondary)),
              ),
          ],
        ),
      ),
      actions: [
        FrameDialogAction(
          key: const ValueKey('changelog-dialog-close-btn'),
          label: strings.changelogGotIt,
          role: FrameDialogActionRole.primary,
          value: null,
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
    required FrameTokens tokens,
    required IconData icon,
    required String title,
    required Color color,
    required int count,
  }) {
    final text = FrameText.of(context);
    return Row(
      children: [
        Icon(icon, size: FrameSize.icon, color: color),
        const SizedBox(width: FrameSpace.x2),
        Text(
          title,
          style: text.label.copyWith(color: color, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: FrameSpace.x2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Text(
            count.toString(),
            style: text.caption.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow({
    required BuildContext context,
    required LinkService links,
    required FrameTokens tokens,
    required ChangelogItem item,
    required Color accentColor,
  }) {
    final text = FrameText.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: FrameSpace.x2),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: item.isFeature ? tokens.accent : tokens.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          if (item.scope != null && item.scope!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(right: FrameSpace.x2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: item.isFeature ? tokens.accent.withValues(alpha: 0.12) : tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: item.isFeature ? tokens.accent.withValues(alpha: 0.25) : tokens.border),
              ),
              child: Text(
                item.scope!,
                style: text.caption.copyWith(
                  color: item.isFeature ? tokens.accent : tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          Expanded(
            child: SelectableText(item.message, style: text.body.copyWith(color: tokens.textPrimary, height: 1.35)),
          ),
          if (item.commitHash != null && item.commitUrl != null) ...[
            const SizedBox(width: FrameSpace.x2),
            PressFeedback(
              child: InkWell(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: () async {
                  final uri = Uri.tryParse(item.commitUrl!);
                  if (uri != null) {
                    await links.openExternal(uri);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    item.commitHash!,
                    style: text.caption.copyWith(color: tokens.textMuted, fontFamily: 'SourceCodePro'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Helper function to display the changelog modal popup.
Future<void> showChangelogDialog({required BuildContext context, required ChangelogRelease release}) {
  return showFrameDialogBuilder<void>(
    context: context,
    builder: (context) => ChangelogDialog(release: release),
  );
}

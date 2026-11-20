import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/update/startup_updates_provider.dart';
import '../../../domain/errors/user_facing_error.dart';
import '../../../ui/frame_error_callout.dart';
import '../../../ui/frame_linear_progress.dart';
import '../../../ui/frame_section.dart';
import '../package_load_states.dart';
import '../../../ui/precision.dart';

/// Pi packages tab: installed packages list, update, pin and remove actions.
/// Loading and error state live in SettingsView and are passed in.
class PackagesSection extends ConsumerWidget {
  const PackagesSection({
    super.key,
    required this.tokens,
    required this.strings,
    required this.isLoading,
    required this.slow,
    required this.loadError,
    required this.packages,
    required this.isWorking,
    required this.updateProgress,
    required this.updateErrorMessage,
    required this.onRetry,
    required this.onUpdateAll,
    required this.onUpdatePackage,
    required this.onPinPackage,
    required this.onRemovePackage,
  });

  final FrameTokens tokens;
  final AppStrings strings;
  final bool isLoading;
  final bool slow;
  final Object? loadError;
  final List<Map<String, dynamic>> packages;
  final bool isWorking;
  final double? updateProgress;
  final String? updateErrorMessage;
  final VoidCallback onRetry;
  final VoidCallback onUpdateAll;
  final void Function(Map<String, dynamic> package) onUpdatePackage;
  final void Function(Map<String, dynamic> package) onPinPackage;
  final void Function(Map<String, dynamic> package) onRemovePackage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = FrameText.of(context);
    if (isLoading) {
      return PackageLoadingView(tokens: tokens, strings: strings, slow: slow, onRetry: onRetry);
    }
    if (loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(FrameSpace.x6),
        children: [
          FrameErrorCallout(
            keyPrefix: 'packages-load',
            title: strings.packagesLoadFailed,
            error: describeError(loadError!, strings),
            strings: strings,
            onRetry: onRetry,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        FrameSection(
          title: strings.packagesInstalledTitle,
          description: strings.packagesInstalledSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PressFeedback(
                  enabled: (isWorking || !packages.any(hasAvailablePiPackageUpdate) ? null : onUpdateAll) != null,
                  child: FilledButton.icon(
                    key: const ValueKey('update-all-pi-packages'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, FrameSize.rowForm)),
                    onPressed: isWorking || !packages.any(hasAvailablePiPackageUpdate) ? null : onUpdateAll,
                    icon: const Icon(Icons.system_update_alt_outlined, size: FrameSize.icon),
                    label: Text(updateProgress == null ? strings.updateAllPackages : strings.updatingPackages),
                  ),
                ),
              ),
              if (isWorking) ...[
                const SizedBox(height: FrameSpace.x3),
                FrameLinearProgress(color: tokens.accent, value: updateProgress),
              ],
              if (updateErrorMessage != null) ...[
                const SizedBox(height: FrameSpace.x3),
                Text(
                  updateErrorMessage!,
                  key: const ValueKey('pi-package-update-error'),
                  style: text.caption.copyWith(color: tokens.danger),
                ),
              ],
              const SizedBox(height: FrameSpace.x3),
              if (packages.isEmpty)
                Text(strings.noPackagesInstalled, style: text.body.copyWith(color: tokens.textMuted)),
              for (final package in packages) _buildPackageRow(context, ref, package),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPackageRow(BuildContext context, WidgetRef ref, Map<String, dynamic> package) {
    final text = FrameText.of(context);
    final source = package['source']?.toString() ?? '';
    final name = package['name']?.toString() ?? source;
    final version = package['version']?.toString() ?? strings.unknownVersion;
    final pin = package['pinnedVersion']?.toString();
    final updateError = package['updateError']?.toString();
    final supportsPin = source.startsWith('npm:');
    final hasUpdate = hasAvailablePiPackageUpdate(package);

    return Container(
      margin: const EdgeInsets.only(bottom: FrameSpace.x2),
      padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x4, vertical: FrameSpace.x3),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: hasUpdate ? tokens.accent.withValues(alpha: 0.3) : tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.extension_outlined,
              color: hasUpdate ? tokens.accent : tokens.textSecondary,
              size: FrameSize.icon,
            ),
          ),
          const SizedBox(width: FrameSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: text.body.copyWith(fontWeight: FontWeight.w600, color: tokens.displayText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (pin != null) ...[
                      const SizedBox(width: FrameSpace.x2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: FrameSpace.x2, vertical: 1),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(tokens.radiusPill),
                          border: Border.all(color: tokens.accent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin, size: 11, color: tokens.accent),
                            const SizedBox(width: 2),
                            Text(
                              pin,
                              style: text.caption.copyWith(
                                color: tokens.accent,
                                fontWeight: FontWeight.w600,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$version${pin == null ? '' : ' · pinned $pin'} · $source',
                  style: text.caption.copyWith(color: tokens.textMuted, fontFamily: tokens.monoFontFamily),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: FrameSpace.x2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (updateError != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    ref
                        .watch(appStringsProvider)
                        .packageUpdateUnavailable(package['latestVersion']?.toString() ?? '?', updateError),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.caption.copyWith(color: tokens.danger),
                  ),
                ),
                const SizedBox(width: FrameSpace.x2),
              ],
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.updatePackageTooltip(name),
                onPressed: isWorking || !hasUpdate ? null : () => onUpdatePackage(package),
                icon: Icon(
                  Icons.system_update_alt_outlined,
                  size: FrameSize.iconLg,
                  color: hasUpdate ? tokens.accent : null,
                ),
              ),
              if (supportsPin)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: strings.pinPackageTooltip(name),
                  onPressed: isWorking ? null : () => onPinPackage(package),
                  icon: const Icon(Icons.push_pin_outlined, size: FrameSize.iconLg),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.removePackageTooltip(name),
                onPressed: isWorking ? null : () => onRemovePackage(package),
                icon: Icon(Icons.delete_outline_outlined, size: FrameSize.iconLg, color: tokens.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

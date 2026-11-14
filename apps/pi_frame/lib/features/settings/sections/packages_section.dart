import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/update/startup_updates_provider.dart';
import '../../../domain/errors/user_facing_error.dart';
import '../../../ui/frame_error_callout.dart';
import '../../../ui/frame_list_row.dart';
import '../../../ui/frame_section.dart';
import '../package_load_states.dart';

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
      return PackageLoadingView(
        tokens: tokens,
        strings: strings,
        slow: slow,
        onRetry: onRetry,
      );
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
                child: FilledButton.icon(
                  key: const ValueKey('update-all-pi-packages'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, FrameSize.rowForm),
                  ),
                  onPressed:
                      isWorking || !packages.any(hasAvailablePiPackageUpdate)
                      ? null
                      : onUpdateAll,
                  icon: const Icon(
                    Icons.system_update_alt,
                    size: FrameSize.icon,
                  ),
                  label: Text(
                    updateProgress == null
                        ? strings.updateAllPackages
                        : strings.updatingPackages,
                  ),
                ),
              ),
              if (isWorking) ...[
                const SizedBox(height: FrameSpace.x3),
                LinearProgressIndicator(
                  color: tokens.accent,
                  value: updateProgress,
                ),
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
                Text(
                  strings.noPackagesInstalled,
                  style: text.body.copyWith(color: tokens.textMuted),
                ),
              for (final package in packages)
                _buildPackageRow(context, ref, package),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPackageRow(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> package,
  ) {
    final text = FrameText.of(context);
    final source = package['source']?.toString() ?? '';
    final name = package['name']?.toString() ?? source;
    final version = package['version']?.toString() ?? strings.unknownVersion;
    final pin = package['pinnedVersion']?.toString();
    final updateError = package['updateError']?.toString();
    final supportsPin = source.startsWith('npm:');
    return FrameListRow(
      name: name,
      secondary: '$version${pin == null ? '' : ' · pinned $pin'} · $source',
      leading: Icon(
        Icons.extension_outlined,
        color: tokens.textSecondary,
        size: FrameSize.icon,
      ),
      // Actions are always visible (not hover-only), so touch users can reach
      // them: they sit in the trailing slot, not in FrameListRow.actions.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updateError != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                ref
                    .watch(appStringsProvider)
                    .packageUpdateUnavailable(
                      package['latestVersion']?.toString() ?? '?',
                      updateError,
                    ),
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
            onPressed: isWorking || !hasAvailablePiPackageUpdate(package)
                ? null
                : () => onUpdatePackage(package),
            icon: const Icon(Icons.system_update_alt, size: FrameSize.iconLg),
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
            icon: Icon(
              Icons.delete_outline,
              size: FrameSize.iconLg,
              color: tokens.danger,
            ),
          ),
        ],
      ),
    );
  }
}

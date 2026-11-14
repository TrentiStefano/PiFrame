import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/update/startup_updates_provider.dart';
import '../../../domain/errors/user_facing_error.dart';
import '../../../ui/frame_error_callout.dart';
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
        padding: const EdgeInsets.all(24),
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
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(
              strings.packagesInstalledTitle,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            );
            final button = FilledButton.icon(
              key: const ValueKey('update-all-pi-packages'),
              onPressed: isWorking || !packages.any(hasAvailablePiPackageUpdate)
                  ? null
                  : onUpdateAll,
              icon: const Icon(Icons.system_update_alt, size: 18),
              label: Text(
                updateProgress == null
                    ? strings.updateAllPackages
                    : strings.updatingPackages,
              ),
            );
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 12), button],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                button,
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          strings.packagesInstalledSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        if (isWorking) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(color: tokens.accent, value: updateProgress),
        ],
        if (updateErrorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            updateErrorMessage!,
            key: const ValueKey('pi-package-update-error'),
            style: TextStyle(color: tokens.danger, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        if (packages.isEmpty)
          Text(
            strings.noPackagesInstalled,
            style: TextStyle(color: tokens.textMuted),
          ),
        for (final package in packages) _buildPackageCard(ref, package),
      ],
    );
  }

  Widget _buildPackageCard(WidgetRef ref, Map<String, dynamic> package) {
    final source = package['source']?.toString() ?? '';
    final name = package['name']?.toString() ?? source;
    final version = package['version']?.toString() ?? strings.unknownVersion;
    final pin = package['pinnedVersion']?.toString();
    final updateError = package['updateError']?.toString();
    final supportsPin = source.startsWith('npm:');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.extension_outlined, color: tokens.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$version${pin == null ? '' : ' · pinned $pin'} · $source',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                  if (updateError != null)
                    Text(
                      ref
                          .watch(appStringsProvider)
                          .packageUpdateUnavailable(
                            package['latestVersion']?.toString() ?? '?',
                            updateError,
                          ),
                      style: TextStyle(color: tokens.danger, fontSize: 11),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: strings.updatePackageTooltip(name),
              onPressed: isWorking || !hasAvailablePiPackageUpdate(package)
                  ? null
                  : () => onUpdatePackage(package),
              icon: const Icon(Icons.system_update_alt, size: 18),
            ),
            if (supportsPin)
              IconButton(
                tooltip: strings.pinPackageTooltip(name),
                onPressed: isWorking ? null : () => onPinPackage(package),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
              ),
            IconButton(
              tooltip: strings.removePackageTooltip(name),
              onPressed: isWorking ? null : () => onRemovePackage(package),
              icon: Icon(Icons.delete_outline, size: 18, color: tokens.danger),
            ),
          ],
        ),
      ),
    );
  }
}

import '../../domain/errors/user_facing_error.dart';
import '../../ui/frame_error_callout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../app/app_version.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../data/update/update_providers.dart';
import '../../domain/update/update_models.dart';

class UpdatesSection extends ConsumerWidget {
  const UpdatesSection({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$min';
  }

  Future<void> _confirmAndInstall(
    BuildContext context,
    WidgetRef ref,
    String? assetName,
  ) async {
    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(strings.confirmInstallDialogTitle),
        content: Text(
          strings.confirmInstallDialogContent(assetName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(strings.installAndRestartBtn),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(updateControllerProvider.notifier).installUpdate();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final updateState = ref.watch(updateControllerProvider);
    final settings = ref.watch(updateSettingsProvider);
    final currentVer = updateState.currentVersion ?? piFrameVersion;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Title & Description
        Text(
          strings.updatesTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.updatesSubtitle,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),

        // 1. Current Version & Check Action Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final checkButton = FilledButton.icon(
                key: const ValueKey('check_for_updates_button'),
                onPressed: updateState.isChecking || updateState.isDownloading
                    ? null
                    : () {
                        ref
                            .read(updateControllerProvider.notifier)
                            .checkForUpdates(isManual: true);
                      },
                icon: updateState.isChecking
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.textPrimary,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(
                  updateState.isChecking
                      ? strings.updatesChecking
                      : strings.updatesCheckBtn,
                ),
              );

              final infoColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        strings.updatesInstalledVersion(currentVer),
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (updateState.status == UpdateStatus.updateAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(
                              color: tokens.accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            strings.updatesNewVersionBadge,
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.lastChecked != null
                        ? strings.updatesLastChecked(_formatDateTime(settings.lastChecked!))
                        : strings.updatesNoRecentCheck,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              );

              final iconBox = Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: Icon(
                  Icons.system_update_outlined,
                  color: tokens.accent,
                  size: 22,
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        iconBox,
                        const SizedBox(width: 14),
                        Expanded(child: infoColumn),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(width: double.infinity, child: checkButton),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconBox,
                  const SizedBox(width: 14),
                  Expanded(child: infoColumn),
                  const SizedBox(width: 12),
                  checkButton,
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // 2. Status Result Card
        if (updateState.status == UpdateStatus.upToDate) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(
                color: tokens.success.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: tokens.success,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.updatesUpToDateTitle,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.updatesUpToDateDesc(currentVer),
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else if (updateState.status == UpdateStatus.error) ...[
          FrameErrorCallout(
            keyPrefix: 'updates',
            title: strings.updatesCheckErrorTitle,
            error: describeError(
              updateState.errorMessage ?? strings.updatesUnexpectedError,
              strings,
            ),
            strings: strings,
            onRetry: () => ref
                .read(updateControllerProvider.notifier)
                .checkForUpdates(isManual: true),
          ),
          const SizedBox(height: 16),
        ] else if (updateState.hasUpdate &&
            updateState.latestRelease != null) ...[
          // Update Available Card
          _buildReleaseCard(context, ref, tokens, updateState, strings),
          const SizedBox(height: 16),
        ],

        // 3. Preferences Card (Periodic Opt-in Check)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.updatesAutoScheduleTitle,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                strings.updatesAutoScheduleSubtitle,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.updatesAutoCheckSwitchTitle,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    strings.updatesAutoCheckSwitchSubtitle,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  value: settings.autoCheckEnabled,
                  activeThumbColor: tokens.accent,
                  onChanged: (enabled) {
                    ref
                        .read(updateSettingsProvider.notifier)
                        .setAutoCheckEnabled(enabled);
                  },
                ),
              ),
              if (settings.autoCheckEnabled) ...[
                const Divider(height: 24),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      strings.updatesCheckFrequencyLabel,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius:
                            BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<UpdateCheckInterval>(
                          value: settings.interval,
                          dropdownColor: tokens.surfaceElevated,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 13,
                          ),
                          items: UpdateCheckInterval.values.map((interval) {
                            return DropdownMenuItem<UpdateCheckInterval>(
                              value: interval,
                              child: Text(strings.updateIntervalLabel(interval)),
                            );
                          }).toList(),
                          onChanged: (newInterval) {
                            if (newInterval != null) {
                              ref
                                  .read(updateSettingsProvider.notifier)
                                  .setInterval(newInterval);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 4. Privacy & Safety Notice Card (Zero-telemetry & user consent)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.security_outlined,
                size: 20,
                color: tokens.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.updatesPrivacySafetyNotice,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReleaseCard(
    BuildContext context,
    WidgetRef ref,
    FrameTokens tokens,
    UpdateState state,
    AppStrings strings,
  ) {
    final release = state.latestRelease!;
    final asset = state.selectedAsset ?? release.findPlatformAsset();
    final isDownloading = state.status == UpdateStatus.downloading;
    final isReady = state.status == UpdateStatus.readyToInstall;
    final isInstalling = state.status == UpdateStatus.installing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.name.isNotEmpty
                          ? release.name
                          : 'PiFrame ${release.tagName}',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      release.publishedAt != null
                          ? strings.updatesPublishedAt(_formatDateTime(release.publishedAt!))
                          : release.tagName,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(updateControllerProvider.notifier)
                      .openReleasePage();
                },
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(strings.updatesNotesOnGithub),
              ),
            ],
          ),

          if (release.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: SingleChildScrollView(
                child: Text(
                  release.body,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontFamily: tokens.monoFontFamily,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (asset != null) ...[
            Text(
              strings.updatesInstallerFile(asset.name, _formatBytes(asset.size)),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
          ],

          if (isDownloading) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: state.downloadProgress > 0 ? state.downloadProgress : null,
                  color: tokens.accent,
                  backgroundColor: tokens.border,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatBytes(state.downloadedBytes)} / ${_formatBytes(state.totalBytes)} (${(state.downloadProgress * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref
                            .read(updateControllerProvider.notifier)
                            .cancelDownload();
                      },
                      child: Text(
                        strings.cancel,
                        style: TextStyle(color: tokens.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else if (isReady) ...[
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _confirmAndInstall(context, ref, asset?.name),
                  icon: const Icon(Icons.install_desktop, size: 16),
                  label: Text(strings.installAndRestartBtn),
                ),
                const SizedBox(width: 12),
                Text(
                  strings.updatesReadyToInstall,
                  style: TextStyle(
                    color: tokens.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else if (isInstalling) ...[
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  strings.updatesLaunchingInstaller,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                if (asset != null)
                  FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(updateControllerProvider.notifier)
                          .downloadUpdate(assetOverride: asset);
                    },
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(strings.updatesDownloadBtn),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () {
                      ref
                          .read(updateControllerProvider.notifier)
                          .openReleasePage();
                    },
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: Text(strings.updatesDownloadManuallyBtn),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

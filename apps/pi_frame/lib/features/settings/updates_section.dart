import '../../domain/errors/user_facing_error.dart';
import '../../ui/frame_error_callout.dart';
import '../../ui/frame_section.dart';
import '../../ui/frame_status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../app/app_version.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../data/update/update_providers.dart';
import '../../domain/update/update_models.dart';
import 'sections/settings_common.dart';

/// Aggiornamenti tab: installed version and check, release details, the
/// periodic check preference and the privacy note. Each block is one
/// [FrameSection]; status uses [FrameStatusTag].
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
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final updateState = ref.watch(updateControllerProvider);
    final settings = ref.watch(updateSettingsProvider);
    final currentVer = updateState.currentVersion ?? piFrameVersion;
    final isUpToDate = updateState.status == UpdateStatus.upToDate;
    final isUpdateAvailable =
        updateState.status == UpdateStatus.updateAvailable;

    final checkButton = FilledButton.icon(
      key: const ValueKey('check_for_updates_button'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, FrameSize.rowForm),
      ),
      onPressed: updateState.isChecking || updateState.isDownloading
          ? null
          : () {
              ref
                  .read(updateControllerProvider.notifier)
                  .checkForUpdates(isManual: true);
            },
      icon: updateState.isChecking
          ? SizedBox(
              width: FrameSize.icon,
              height: FrameSize.icon,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.textPrimary,
              ),
            )
          : const Icon(Icons.refresh, size: FrameSize.icon),
      label: Text(
        updateState.isChecking
            ? strings.updatesChecking
            : strings.updatesCheckBtn,
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        Text(
          strings.updatesTitle,
          style: text.title.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: FrameSpace.x1),
        Text(
          strings.updatesSubtitle,
          style: text.body.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: FrameSpace.x4),

        // 1. Installed version and the check action.
        FrameSection(
          title: strings.updatesInstalledVersion(currentVer),
          description: isUpToDate
              ? strings.updatesUpToDateDesc(currentVer)
              : settings.lastChecked != null
              ? strings.updatesLastChecked(_formatDateTime(settings.lastChecked!))
              : strings.updatesNoRecentCheck,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FrameSpace.x3,
            runSpacing: FrameSpace.x2,
            children: [
              if (isUpdateAvailable)
                FrameStatusTag(
                  key: const ValueKey('updates-available-tag'),
                  label: strings.updatesNewVersionBadge,
                  tone: FrameStatusTone.info,
                ),
              if (isUpToDate)
                FrameStatusTag(
                  key: const ValueKey('updates-up-to-date-tag'),
                  label: strings.updatesUpToDateTitle,
                  tone: FrameStatusTone.success,
                ),
              checkButton,
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x8),

        if (updateState.status == UpdateStatus.error) ...[
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
          const SizedBox(height: FrameSpace.x8),
        ] else if (updateState.hasUpdate &&
            updateState.latestRelease != null) ...[
          _buildReleaseSection(context, ref, tokens, updateState, strings),
          const SizedBox(height: FrameSpace.x8),
        ],

        // 2. Periodic check preference.
        FrameSection(
          title: strings.updatesAutoScheduleTitle,
          description: strings.updatesAutoScheduleSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.updatesAutoCheckSwitchTitle,
                    style: text.body.copyWith(color: tokens.textPrimary),
                  ),
                  subtitle: Text(
                    strings.updatesAutoCheckSwitchSubtitle,
                    style: text.caption.copyWith(color: tokens.textMuted),
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
                const SizedBox(height: FrameSpace.x2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.updatesCheckFrequencyLabel,
                        style: text.label.copyWith(color: tokens.textSecondary),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: buildSettingsFieldBox(
                        tokens,
                        DropdownButtonHideUnderline(
                          child: DropdownButton<UpdateCheckInterval>(
                            key: const ValueKey('updates-interval-dropdown'),
                            isExpanded: true,
                            isDense: true,
                            value: settings.interval,
                            dropdownColor: tokens.surfaceElevated,
                            style: text.body.copyWith(color: tokens.textPrimary),
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
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x6),

        // 3. Privacy and safety note: flat, no card.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.security_outlined,
              size: FrameSize.iconLg,
              color: tokens.accent,
            ),
            const SizedBox(width: FrameSpace.x3),
            Expanded(
              child: Text(
                strings.updatesPrivacySafetyNotice,
                style: text.caption.copyWith(color: tokens.textMuted, height: 1.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReleaseSection(
    BuildContext context,
    WidgetRef ref,
    FrameTokens tokens,
    UpdateState state,
    AppStrings strings,
  ) {
    final text = FrameText.of(context);
    final release = state.latestRelease!;
    final asset = state.selectedAsset ?? release.findPlatformAsset();
    final isDownloading = state.status == UpdateStatus.downloading;
    final isReady = state.status == UpdateStatus.readyToInstall;
    final isInstalling = state.status == UpdateStatus.installing;

    return FrameSection(
      title: release.name.isNotEmpty
          ? release.name
          : 'PiFrame ${release.tagName}',
      description: release.publishedAt != null
          ? strings.updatesPublishedAt(_formatDateTime(release.publishedAt!))
          : release.tagName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, FrameSize.rowForm),
              ),
              onPressed: () {
                ref
                    .read(updateControllerProvider.notifier)
                    .openReleasePage();
              },
              icon: const Icon(Icons.open_in_new, size: FrameSize.icon),
              label: Text(strings.updatesNotesOnGithub),
            ),
          ),

          if (release.body.isNotEmpty) ...[
            const SizedBox(height: FrameSpace.x3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  release.body,
                  style: text.mono.copyWith(color: tokens.textSecondary),
                ),
              ),
            ),
          ],

          const SizedBox(height: FrameSpace.x3),

          if (asset != null) ...[
            Text(
              strings.updatesInstallerFile(asset.name, _formatBytes(asset.size)),
              style: text.caption.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: FrameSpace.x2),
          ],

          if (isDownloading) ...[
            LinearProgressIndicator(
              value: state.downloadProgress > 0 ? state.downloadProgress : null,
              color: tokens.accent,
              backgroundColor: tokens.border,
            ),
            const SizedBox(height: FrameSpace.x2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatBytes(state.downloadedBytes)} / ${_formatBytes(state.totalBytes)} (${(state.downloadProgress * 100).toStringAsFixed(0)}%)',
                  style: text.mono.copyWith(color: tokens.textMuted),
                ),
                TextButton(
                  onPressed: () {
                    ref
                        .read(updateControllerProvider.notifier)
                        .cancelDownload();
                  },
                  child: Text(
                    strings.cancel,
                    style: text.caption.copyWith(color: tokens.danger),
                  ),
                ),
              ],
            ),
          ] else if (isReady) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: FrameSpace.x3,
              runSpacing: FrameSpace.x2,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, FrameSize.rowForm),
                  ),
                  onPressed: () => _confirmAndInstall(context, ref, asset?.name),
                  icon: const Icon(Icons.install_desktop, size: FrameSize.icon),
                  label: Text(strings.installAndRestartBtn),
                ),
                FrameStatusTag(
                  label: strings.updatesReadyToInstall,
                  tone: FrameStatusTone.success,
                ),
              ],
            ),
          ] else if (isInstalling) ...[
            Row(
              children: [
                SizedBox(
                  width: FrameSize.icon,
                  height: FrameSize.icon,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: FrameSpace.x3),
                Text(
                  strings.updatesLaunchingInstaller,
                  style: text.body.copyWith(color: tokens.textPrimary),
                ),
              ],
            ),
          ] else ...[
            if (asset != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, FrameSize.rowForm),
                ),
                onPressed: () {
                  ref
                      .read(updateControllerProvider.notifier)
                      .downloadUpdate(assetOverride: asset);
                },
                icon: const Icon(Icons.download, size: FrameSize.icon),
                label: Text(strings.updatesDownloadBtn),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, FrameSize.rowForm),
                ),
                onPressed: () {
                  ref
                      .read(updateControllerProvider.notifier)
                      .openReleasePage();
                },
                icon: const Icon(Icons.open_in_browser, size: FrameSize.icon),
                label: Text(strings.updatesDownloadManuallyBtn),
              ),
          ],
        ],
      ),
    );
  }
}

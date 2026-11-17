import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/daemon/daemon_locator.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/notifications/notification_providers.dart';
import '../../../ui/frame_activity_indicator.dart';
import '../../../ui/frame_dialog.dart';
import '../../../ui/frame_section.dart';
import '../../../ui/frame_status_tag.dart';
import 'settings_common.dart';
import '../../../ui/precision.dart';

/// Daemon tab: connection status, restart action, idle timeout, notifications.
/// The daemon status uses the same tag vocabulary as Diagnostica.
class DaemonSection extends ConsumerWidget {
  const DaemonSection({
    super.key,
    required this.tokens,
    required this.strings,
    required this.endpoint,
    required this.isLoadingConfig,
    required this.workerIdleTimeoutMinutes,
    required this.configStatusMessage,
    required this.isRestartingDaemon,
    required this.onRestartDaemon,
    required this.onUpdateTimeout,
    this.runActive = false,
  });

  final FrameTokens tokens;
  final AppStrings strings;
  final DaemonEndpoint? endpoint;
  final bool isLoadingConfig;
  final int workerIdleTimeoutMinutes;
  final String? configStatusMessage;
  final bool isRestartingDaemon;
  final VoidCallback onRestartDaemon;
  final void Function(int minutes) onUpdateTimeout;

  /// True while an agent run is in progress. A restart then asks first.
  final bool runActive;

  /// Restarts directly when idle; while a run is active, asks first because
  /// the running session is reconnected.
  Future<void> _requestRestart(BuildContext context) async {
    if (!runActive) {
      onRestartDaemon();
      return;
    }
    final confirmed = await showFrameDialog<bool>(
      context: context,
      dialog: FrameDialog<bool>(
        title: strings.daemonRestartConfirmTitle,
        body: Text(
          strings.daemonRestartConfirmBody,
          key: const ValueKey('settings-daemon-restart-confirm-body'),
        ),
        actions: [
          FrameDialogAction<bool>(
            label: strings.cancel,
            role: FrameDialogActionRole.cancel,
            value: false,
          ),
          FrameDialogAction<bool>(
            label: strings.daemonRestartConfirmAction,
            role: FrameDialogActionRole.primary,
            value: true,
            key: const ValueKey('settings-daemon-restart-confirm-btn'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onRestartDaemon();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = FrameText.of(context);
    final endpoint = this.endpoint;
    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        FrameSection(
          title: strings.daemonStatusTitle,
          description: strings.daemonStatusSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rows sit flat inside the section: one border level only.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.labelStatus,
                          style: text.body.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                      FrameStatusTag(
                        key: const ValueKey('settings-daemon-status'),
                        label: endpoint == null
                            ? strings.labelNotConnected
                            : strings.labelEndpointDetected,
                        tone: endpoint == null
                            ? FrameStatusTone.danger
                            : FrameStatusTone.success,
                      ),
                    ],
                  ),
                  buildSettingsInfoRow(
                    tokens,
                    strings.labelHttpWsPort,
                    endpoint != null
                        ? '127.0.0.1:${endpoint.port}'
                        : strings.labelConnecting,
                  ),
                  buildSettingsInfoRow(
                    tokens,
                    strings.labelProtocol,
                    strings.protocolPcp1,
                  ),
                ],
              ),
              const SizedBox(height: FrameSpace.x4),
              Align(
                alignment: Alignment.centerLeft,
                child: PressFeedback(
                  child: OutlinedButton.icon(
                    key: const ValueKey('settings-restart-daemon-btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.textPrimary,
                      side: BorderSide(color: tokens.borderStrong),
                      minimumSize: const Size(0, FrameSize.rowForm),
                    ),
                    icon: isRestartingDaemon
                        ? FrameActivityIndicator(
                            size: FrameSize.icon,
                            strokeWidth: 2,
                            color: tokens.accent,
                          )
                        : const Icon(
                            Icons.restart_alt_outlined,
                            size: FrameSize.icon,
                          ),
                    label: Text(
                      isRestartingDaemon
                          ? strings.restartingDaemonStatus
                          : strings.restartDaemonBtn,
                    ),
                    onPressed: isRestartingDaemon
                        ? null
                        : () => _requestRestart(context),
                  ),
                ),
              ),
              const SizedBox(height: FrameSpace.x2),
              Text(
                strings.daemonRestartConsequence,
                key: const ValueKey('settings-daemon-restart-consequence'),
                style: text.caption.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          title: strings.workerIdleTimeoutTitle,
          description: strings.workerIdleTimeoutSubtitle,
          child: isLoadingConfig
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: FrameActivityIndicator(
                    size: FrameSize.iconLg,
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                )
              : Wrap(
                  spacing: FrameSpace.x4,
                  runSpacing: FrameSpace.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: buildSettingsFieldBox(
                        tokens,
                        DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            key: const ValueKey(
                              'settings-idle-timeout-dropdown',
                            ),
                            isExpanded: true,
                            isDense: true,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMd,
                            ),
                            value: workerIdleTimeoutMinutes,
                            dropdownColor: tokens.surfaceElevated,
                            style: text.body.copyWith(
                              color: tokens.textPrimary,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(strings.timeoutNever),
                              ),
                              DropdownMenuItem(
                                value: 5,
                                child: Text(strings.timeout5Min),
                              ),
                              DropdownMenuItem(
                                value: 15,
                                child: Text(strings.timeout15Min),
                              ),
                              DropdownMenuItem(
                                value: 30,
                                child: Text(strings.timeout30Min),
                              ),
                              DropdownMenuItem(
                                value: 60,
                                child: Text(strings.timeout1Hour),
                              ),
                              DropdownMenuItem(
                                value: 120,
                                child: Text(strings.timeout2Hours),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                onUpdateTimeout(val);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    if (configStatusMessage != null)
                      Text(
                        configStatusMessage!,
                        style: text.label.copyWith(color: tokens.textPrimary),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: FrameSpace.x8),
        FrameSection(
          title: strings.notificationsSectionTitle,
          description: strings.notificationsSectionSubtitle,
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: FrameSpace.x2,
              ),
              title: Text(
                strings.notificationsSwitchTitle,
                style: text.body.copyWith(color: tokens.textPrimary),
              ),
              value: ref.watch(notificationsEnabledProvider),
              activeThumbColor: tokens.accent,
              onChanged: (val) {
                ref.read(notificationsEnabledProvider.notifier).state = val;
              },
            ),
          ),
        ),
      ],
    );
  }
}

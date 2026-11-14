import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../../data/daemon/daemon_locator.dart';
import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_settings.dart';
import '../../../data/notifications/notification_providers.dart';
import 'settings_common.dart';

/// Daemon tab: connection status, restart action, idle timeout, notifications.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpoint = this.endpoint;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.daemonStatusTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.daemonStatusSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        buildSettingsInfoCard(tokens, [
          buildSettingsInfoRow(
            tokens,
            strings.labelHttpWsPort,
            endpoint != null
                ? '127.0.0.1:${endpoint.port}'
                : strings.labelConnecting,
          ),
          buildSettingsInfoRow(
            tokens,
            strings.labelStatus,
            endpoint == null
                ? strings.labelNotConnected
                : strings.labelEndpointDetected,
          ),
          buildSettingsInfoRow(
            tokens,
            strings.labelProtocol,
            strings.protocolPcp1,
          ),
        ]),
        const SizedBox(height: 24),
        Text(
          strings.workerIdleTimeoutTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.workerIdleTimeoutSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        isLoadingConfig
            ? Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  ),
                ),
              )
            : Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      border: Border.all(color: tokens.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        borderRadius: BorderRadius.circular(tokens.radiusMd),
                        value: workerIdleTimeoutMinutes,
                        dropdownColor: tokens.surfaceElevated,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 14,
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
                  const SizedBox(width: 16),
                  if (configStatusMessage != null)
                    Text(
                      configStatusMessage!,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.surfaceElevated,
              foregroundColor: tokens.textPrimary,
            ),
            icon: isRestartingDaemon
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                : const Icon(Icons.restart_alt, size: 16),
            label: Text(
              isRestartingDaemon
                  ? strings.restartingDaemonStatus
                  : strings.restartDaemonBtn,
            ),
            onPressed: isRestartingDaemon ? null : onRestartDaemon,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          strings.notificationsSectionTitle,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.notificationsSectionSubtitle,
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              strings.notificationsSwitchTitle,
              style: TextStyle(color: tokens.textPrimary, fontSize: 13),
            ),
            value: ref.watch(notificationsEnabledProvider),
            activeThumbColor: tokens.accent,
            onChanged: (val) {
              ref.read(notificationsEnabledProvider.notifier).state = val;
            },
          ),
        ),
      ],
    );
  }
}

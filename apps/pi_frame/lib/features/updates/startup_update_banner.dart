import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/update/startup_updates_provider.dart';

class StartupUpdateBanner extends ConsumerWidget {
  /// Distance from the top of the enclosing Stack. The shell passes the offset
  /// below the title bar, so the banner never covers the composer or the
  /// title-bar controls.
  const StartupUpdateBanner({super.key, this.top = 56});

  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(startupUpdatesProvider);
    final strings = ref.watch(appStringsProvider);
    final tokens = context.tokens;

    if (!state.shouldShowBanner) {
      return const SizedBox.shrink();
    }

    final details = <String>[];
    if (state.piHasUpdate) {
      details.add(
        'Pi CLI: ${state.currentPiVersion ?? '?'} → ${state.latestPiVersion ?? '?'}',
      );
    }
    if (state.outdatedPackages.isNotEmpty) {
      final names = state.outdatedPackages.map((p) => p.name).join(', ');
      details.add(
        '${state.outdatedPackages.length} ${strings.updateNoticePackages}: $names',
      );
    }
    if (state.error != null) {
      details.add(strings.packageUpdateCheckFailed(state.error!));
    }

    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: Align(
        alignment: Alignment.topRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            elevation: 0,
            color: tokens.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              side: BorderSide(color: tokens.border),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.signalWarning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      Icons.system_update_alt,
                      color: tokens.signalWarning,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.updateNoticeTitle,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: tokens.uiFontFamily,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details.join(' • '),
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontFamily: tokens.uiFontFamily,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const ValueKey('startup-update-open-btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    onPressed: () {
                      ref.read(settingsTabIndexProvider.notifier).state =
                          state.piHasUpdate ? 0 : 1;
                      ref.read(showSettingsProvider.notifier).state = true;
                      ref.read(startupUpdatesProvider.notifier).dismiss();
                    },
                    child: Text(
                      strings.updateNoticeOpenSettings,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: tokens.uiFontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const ValueKey('startup-update-dismiss-btn'),
                    visualDensity: VisualDensity.compact,
                    tooltip: strings.updateNoticeDismiss,
                    icon: Icon(Icons.close, size: 16, color: tokens.textMuted),
                    onPressed: () {
                      ref.read(startupUpdatesProvider.notifier).dismiss();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/update/startup_updates_provider.dart';

/// Startup notice about available Pi and package updates.
///
/// It takes layout space and never overlays other controls:
/// - [inRail] true: a narrow block at the top of the sessions rail. Text wraps
///   inside the rail and the buttons sit below it.
/// - [inRail] false: a full-width row directly under the title bar. It is used
///   when the rail is hidden, collapsed, or the layout is compact.
class StartupUpdateBanner extends ConsumerWidget {
  const StartupUpdateBanner({super.key, this.inRail = false});

  final bool inRail;

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

    final icon = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tokens.signalWarning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Icon(Icons.system_update_alt, color: tokens.signalWarning, size: 20),
    );

    final title = Text(
      strings.updateNoticeTitle,
      style: TextStyle(
        color: tokens.textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: 13,
        fontFamily: tokens.uiFontFamily,
      ),
    );

    final detailText = Text(
      details.join(' • '),
      style: TextStyle(
        color: tokens.textSecondary,
        fontSize: 12,
        fontFamily: tokens.uiFontFamily,
      ),
      maxLines: inRail ? 3 : 2,
      overflow: TextOverflow.ellipsis,
    );

    final openButton = FilledButton(
      key: const ValueKey('startup-update-open-btn'),
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    );

    final dismissButton = IconButton(
      key: const ValueKey('startup-update-dismiss-btn'),
      visualDensity: VisualDensity.compact,
      tooltip: strings.updateNoticeDismiss,
      icon: Icon(Icons.close, size: 16, color: tokens.textMuted),
      onPressed: () {
        ref.read(startupUpdatesProvider.notifier).dismiss();
      },
    );

    final Widget content;
    if (inRail) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 2), detailText],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: openButton),
              const SizedBox(width: 4),
              dismissButton,
            ],
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 2), detailText],
            ),
          ),
          const SizedBox(width: 12),
          openButton,
          const SizedBox(width: 6),
          dismissButton,
        ],
      );
    }

    return Container(
      margin: inRail
          ? const EdgeInsets.fromLTRB(8, 8, 8, 0)
          : const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        elevation: 0,
        color: tokens.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.border),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: inRail ? 12 : 16,
            vertical: 12,
          ),
          child: content,
        ),
      ),
    );
  }
}

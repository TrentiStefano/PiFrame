import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../domain/session/agent_status.dart';
import '../../ui/motion.dart';

class AgentStatusBadge extends StatelessWidget {
  final AgentStatus status;
  final bool onDisplay;
  const AgentStatusBadge({
    super.key,
    required this.status,
    this.onDisplay = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasScope =
        context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() !=
            null ||
        context.findAncestorWidgetOfExactType<ProviderScope>() != null;
    if (hasScope) {
      return Consumer(
        builder: (context, ref, _) {
          final strings = ref.watch(appStringsProvider);
          return _buildBadge(context, tokens, strings);
        },
      );
    }
    return _buildBadge(context, tokens, const AppStrings(AppLanguage.it));
  }

  Widget _buildBadge(
    BuildContext context,
    FrameTokens tokens,
    AppStrings strings,
  ) {
    final label = strings.agentStatusLabel(status);
    final foreground = switch (status) {
      AgentStatus.idle || AgentStatus.settled => tokens.success,
      AgentStatus.working => tokens.agentWorking,
      AgentStatus.retrying => tokens.warning,
      AgentStatus.compacting => tokens.info,
      AgentStatus.awaitingUser => tokens.agentAwaitingUser,
      AgentStatus.error || AgentStatus.workerError => tokens.danger,
    };
    if (onDisplay) {
      final signal = switch (status) {
        AgentStatus.error || AgentStatus.workerError => tokens.signalDanger,
        AgentStatus.working ||
        AgentStatus.retrying ||
        AgentStatus.awaitingUser => tokens.signalWarning,
        _ => tokens.displayText,
      };
      return Semantics(
        liveRegion: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: signal,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.borderStrong, width: 1),
              ),
            ),
            const SizedBox(width: FrameSpace.x2),
            Text(
              label,
              style: FrameText.of(context).label
                  .copyWith(color: tokens.displayText),
            ),
          ],
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: FrameMotion.reduced(context)
            ? FrameMotion.instant
            : FrameMotion.micro,
        curve: FrameMotion.enterCurve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            foreground.withValues(alpha: 0.12),
            tokens.surface,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.borderStrong, width: 1),
              ),
            ),
            const SizedBox(width: FrameSpace.x2),
            Text(
              label,
              style: FrameText.of(context).label.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

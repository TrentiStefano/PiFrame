import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../domain/session/agent_status.dart';

class AgentStatusBadge extends StatelessWidget {
  final AgentStatus status;

  const AgentStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Color bg;
    Color fg;

    switch (status) {
      case AgentStatus.idle:
      case AgentStatus.settled:
        bg = tokens.success.withValues(alpha: 0.15);
        fg = tokens.success;
        break;
      case AgentStatus.working:
        bg = tokens.agentWorking.withValues(alpha: 0.15);
        fg = tokens.agentWorking;
        break;
      case AgentStatus.retrying:
        bg = tokens.warning.withValues(alpha: 0.15);
        fg = tokens.warning;
        break;
      case AgentStatus.compacting:
        bg = tokens.info.withValues(alpha: 0.15);
        fg = tokens.info;
        break;
      case AgentStatus.awaitingUser:
        bg = tokens.agentAwaitingUser.withValues(alpha: 0.15);
        fg = tokens.agentAwaitingUser;
        break;
      case AgentStatus.error:
      case AgentStatus.workerError:
        bg = tokens.danger.withValues(alpha: 0.15);
        fg = tokens.danger;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

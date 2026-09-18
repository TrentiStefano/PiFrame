import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';
import '../status/agent_status_badge.dart';

class TranscriptView extends ConsumerWidget {
  final String sessionId;

  const TranscriptView({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(sessionId));

    return Column(
      children: [
        // Session Header with Status Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sessionState.sessionName ?? sessionId,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sessionState.cwd.isNotEmpty ? sessionState.cwd : 'Nessuna cartella aperta',
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
                ],
              ),
              AgentStatusBadge(status: sessionState.agentStatus),
            ],
          ),
        ),

        // Transcript messages list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: sessionState.entries.length + (sessionState.isStreaming ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < sessionState.entries.length) {
                final entry = sessionState.entries[index];
                final isUser = entry.role == 'user';

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser ? tokens.userBubble : tokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUser ? 'Tu' : 'Assistente',
                          style: TextStyle(
                            color: isUser ? tokens.accent : tokens.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          entry.text,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Live streaming indicator / message block
              final liveText = sessionState.currentStreamingText;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.accent.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              color: tokens.accent,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Assistente (in streaming...)',
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        liveText.isEmpty ? 'Elaborazione in corso...' : liveText,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/session/session_state.dart';
import 'tool_card.dart';

class ToolTimeline extends StatelessWidget {
  final List<ToolExecutionState> toolCalls;

  const ToolTimeline({super.key, required this.toolCalls});

  @override
  Widget build(BuildContext context) {
    if (toolCalls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: toolCalls.map((t) => ToolCard(key: ValueKey(t.toolCallId), tool: t)).toList(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../domain/session/session_state.dart';

class ToolCard extends StatefulWidget {
  final ToolExecutionState tool;

  const ToolCard({super.key, required this.tool});

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _isExpanded = false;

  IconData _getToolIcon(String name) {
    switch (name.toLowerCase()) {
      case 'read':
      case 'read_file':
        return Icons.file_open_outlined;
      case 'write':
      case 'write_file':
        return Icons.save_outlined;
      case 'edit':
      case 'edit_file':
        return Icons.edit_note_outlined;
      case 'bash':
      case 'terminal':
      case 'exec':
        return Icons.terminal_outlined;
      case 'grep':
      case 'find':
      case 'search':
        return Icons.search_outlined;
      default:
        return Icons.build_circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tool = widget.tool;
    final isBash = tool.toolName.toLowerCase() == 'bash';

    // Format arg preview
    String argPreview = '';
    if (tool.args.containsKey('path')) {
      argPreview = tool.args['path'].toString();
    } else if (tool.args.containsKey('file')) {
      argPreview = tool.args['file'].toString();
    } else if (tool.args.containsKey('command')) {
      argPreview = tool.args['command'].toString();
    } else if (tool.args.isNotEmpty) {
      argPreview = tool.args.values.first.toString();
    }

    final hasOutput = tool.output.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: tool.isError
              ? tokens.agentError
              : tool.isRunning
              ? tokens.agentWorking.withValues(alpha: 0.6)
              : tokens.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          TextButton(
            onPressed: hasOutput
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _getToolIcon(tool.toolName),
                    size: 15,
                    color: tool.isError
                        ? tokens.agentError
                        : tool.isRunning
                        ? tokens.agentWorking
                        : tokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tool.toolName,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 12,
                      fontFamily: tokens.uiFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (argPreview.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        argPreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isBash ? tokens.syntaxString : tokens.accent,
                          fontSize: 11.5,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (tool.durationMs != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${tool.durationMs}ms',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (tool.isRunning)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: tokens.agentWorking,
                      ),
                    )
                  else if (tool.isError)
                    Icon(
                      Icons.error_outline,
                      size: 14,
                      color: tokens.agentError,
                    )
                  else
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: tokens.agentSettled,
                    ),
                  if (hasOutput) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Output body (if expanded or running)
          if (hasOutput && (_isExpanded || tool.isRunning)) ...[
            Divider(color: tokens.border, height: 1),
            Container(
              padding: const EdgeInsets.all(8),
              constraints: BoxConstraints(maxHeight: _isExpanded ? 320 : 120),
              decoration: BoxDecoration(
                color: isBash
                    ? tokens.background
                    : tokens.surfaceElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(tokens.radiusSm),
                  bottomRight: Radius.circular(tokens.radiusSm),
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  tool.output,
                  style: TextStyle(
                    color: tool.isError
                        ? tokens.agentError
                        : tokens.textSecondary,
                    fontSize: 11.5,
                    fontFamily: tokens.monoFontFamily,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

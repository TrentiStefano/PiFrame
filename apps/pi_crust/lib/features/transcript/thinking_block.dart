import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class ThinkingBlock extends StatefulWidget {
  final String thinkingText;
  final bool isStreaming;

  const ThinkingBlock({
    super.key,
    required this.thinkingText,
    this.isStreaming = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.thinkingText.trim().isEmpty && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    final tokens = context.tokens;
    final words = widget.thinkingText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final firstLine = widget.thinkingText.trim().split('\n').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: tokens.thinking.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Collapsed header / toggle
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: tokens.thinking,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ragionamento',
                    style: TextStyle(
                      color: tokens.thinking,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: tokens.thinking.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusPill),
                    ),
                    child: Text(
                      widget.isStreaming && widget.thinkingText.isEmpty
                          ? 'Pensando...'
                          : '$words parole',
                      style: TextStyle(
                        color: tokens.thinking,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isExpanded ? '' : firstLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: tokens.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded body
          if (_isExpanded) ...[
            Divider(color: tokens.border, height: 1),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated.withValues(alpha: 0.4),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(tokens.radiusSm),
                  bottomRight: Radius.circular(tokens.radiusSm),
                ),
              ),
              child: SelectableText(
                widget.thinkingText.isEmpty ? 'Nessun dettaglio' : widget.thinkingText,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.5,
                  fontFamily: tokens.monoFontFamily,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

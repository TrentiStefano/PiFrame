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
    final words = widget.thinkingText
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
    final firstLine = widget.thinkingText.trim().split('\n').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context) || widget.isStreaming
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              expanded: _isExpanded,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: tokens.thinking,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 17,
                      color: tokens.thinking,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Ragionamento',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.isStreaming && widget.thinkingText.isEmpty
                            ? 'Pensando...'
                            : '$words parole',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textMuted, fontSize: 11),
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width > 700)
                      Expanded(
                        flex: 3,
                        child: Text(
                          _isExpanded ? '' : firstLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: tokens.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: SelectableText(
                  widget.thinkingText.isEmpty
                      ? 'Nessun dettaglio'
                      : widget.thinkingText,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

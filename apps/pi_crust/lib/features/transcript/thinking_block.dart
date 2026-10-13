import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class ThinkingBlock extends StatefulWidget {
  final String thinkingText;
  final bool isStreaming;
  final bool? isExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const ThinkingBlock({
    super.key,
    required this.thinkingText,
    this.isStreaming = false,
    this.isExpanded,
    this.onExpansionChanged,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  late bool _internalExpanded;

  @override
  void initState() {
    super.initState();
    _internalExpanded = widget.isExpanded ?? false;
  }

  @override
  void didUpdateWidget(ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != null && widget.isExpanded != oldWidget.isExpanded) {
      _internalExpanded = widget.isExpanded!;
    }
  }

  bool get _effectiveExpanded => widget.isExpanded ?? _internalExpanded;

  void _toggleExpanded() {
    final next = !_effectiveExpanded;
    if (widget.isExpanded == null) {
      setState(() => _internalExpanded = next);
    }
    widget.onExpansionChanged?.call(next);
  }

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
        border: Border.all(color: tokens.border),
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
              expanded: _effectiveExpanded,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: _toggleExpanded,
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
                          _effectiveExpanded ? '' : firstLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Icon(
                      _effectiveExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: tokens.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_effectiveExpanded)
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

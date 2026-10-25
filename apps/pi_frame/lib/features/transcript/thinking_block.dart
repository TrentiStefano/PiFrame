import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

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
    if (widget.isExpanded != null &&
        widget.isExpanded != oldWidget.isExpanded) {
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

  static int _countWords(String text) {
    var count = 0;
    var inWord = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      final isWhitespace = code <= 32;
      if (!isWhitespace && !inWord) {
        inWord = true;
        count++;
      } else if (isWhitespace) {
        inWord = false;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.thinkingText.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;
    final words = _countWords(trimmed);
    final newlineIdx = trimmed.indexOf('\n');
    final firstLine = newlineIdx >= 0
        ? trimmed.substring(0, newlineIdx)
        : trimmed;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: _effectiveExpanded,
          child: InkWell(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: tokens.thinking,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Ragionamento',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$words parole',
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                  if (MediaQuery.sizeOf(context).width > 700) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _effectiveExpanded ? '' : firstLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textMuted, fontSize: 11),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  Icon(
                    _effectiveExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_effectiveExpanded)
          Container(
            margin: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: tokens.borderStrong, width: 2),
              ),
            ),
            child: SelectableText(
              widget.thinkingText,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
      ],
    );

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        child: widget.isStreaming
            ? content
            : AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: content,
              ),
      ),
    );
  }
}

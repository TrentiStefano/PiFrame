import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class SlashMenu extends StatelessWidget {
  final List<Map<String, dynamic>> commands;
  final String filter;
  final ValueChanged<Map<String, dynamic>> onSelect;
  /// Localized label for a command source (Pi, estensione, prompt, skill).
  final String Function(String source) sourceLabel;

  /// Keyboard-highlighted row in [filtered] order.
  final int selectedIndex;

  const SlashMenu({
    super.key,
    required this.commands,
    required this.filter,
    required this.onSelect,
    required this.sourceLabel,
    this.selectedIndex = 0,
  });

  /// Commands matching [filter] (the composer text, with or without the leading '/').
  static List<Map<String, dynamic>> filtered(
    List<Map<String, dynamic>> commands,
    String filter,
  ) {
    final clean = (filter.startsWith('/') ? filter.substring(1) : filter)
        .toLowerCase();
    return commands.where((cmd) {
      final name = (cmd['name'] as String? ?? '').toLowerCase();
      final desc = (cmd['description'] as String? ?? '').toLowerCase();
      return name.contains(clean) || desc.contains(clean);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final items = filtered(commands, filter);

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: child,
        ),
      ),
      child: Material(
        color: tokens.surface.withValues(alpha: 0),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: tokens.overlay,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: tokens.border),
            itemBuilder: (context, index) {
              final cmd = items[index];
              final name = cmd['name'] as String? ?? '';
              final desc = cmd['description'] as String? ?? '';
              final argumentHint = cmd['argumentHint'] as String? ?? '';
              final source = cmd['source'] as String? ?? 'prompt';
              final selected = index == selectedIndex;

              final row = InkWell(
                key: ValueKey('slash-menu-item-$name'),
                onTap: () => onSelect(cmd),
                hoverColor: tokens.surface,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? tokens.accent.withValues(alpha: 0.12)
                        : tokens.accent.withValues(alpha: 0),
                    border: Border(
                      left: BorderSide(
                        color: tokens.accent.withValues(
                          alpha: selected ? 1 : 0,
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.terminal_rounded,
                        size: 13,
                        color: selected ? tokens.accent : tokens.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          '/$name${argumentHint.isEmpty ? '' : ' $argumentHint'}',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontFamily: tokens.monoFontFamily,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          desc,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel(source),
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return selected ? _KeepVisible(child: row) : row;
            },
          ),
        ),
      ),
    );
  }
}

/// Scrolls the keyboard-highlighted row into view.
class _KeepVisible extends StatefulWidget {
  const _KeepVisible({required this.child});
  final Widget child;

  @override
  State<_KeepVisible> createState() => _KeepVisibleState();
}

class _KeepVisibleState extends State<_KeepVisible> {
  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 100),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 100),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
    return widget.child;
  }
}

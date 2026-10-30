import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class SlashMenu extends StatelessWidget {
  final List<Map<String, dynamic>> commands;
  final String filter;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const SlashMenu({
    super.key,
    required this.commands,
    required this.filter,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cleanFilter = filter.startsWith('/')
        ? filter.substring(1).toLowerCase()
        : filter.toLowerCase();

    final filtered = commands.where((cmd) {
      final name = (cmd['name'] as String? ?? '').toLowerCase();
      final desc = (cmd['description'] as String? ?? '').toLowerCase();
      return name.contains(cleanFilter) || desc.contains(cleanFilter);
    }).toList();

    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
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
          itemCount: filtered.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
          itemBuilder: (context, index) {
            final cmd = filtered[index];
            final name = cmd['name'] as String? ?? '';
            final desc = cmd['description'] as String? ?? '';
            final argumentHint = cmd['argumentHint'] as String? ?? '';
            final source = cmd['source'] as String? ?? 'prompt';

            return InkWell(
              onTap: () => onSelect(cmd),
              hoverColor: tokens.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
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
                      source,
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
          },
        ),
      ),
    );
  }
}

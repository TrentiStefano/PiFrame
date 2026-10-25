import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class FileMentionMenu extends StatelessWidget {
  final List<Map<String, dynamic>> files;
  final String query;
  final int selectedIndex;
  final ValueChanged<String> onSelect;

  const FileMentionMenu({
    super.key,
    required this.files,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
  });

  IconData _getFileIcon(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return Icons.code;
    if (lower.endsWith('.js') || lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.jsx')) {
      return Icons.javascript;
    }
    if (lower.endsWith('.json') || lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return Icons.data_object;
    }
    if (lower.endsWith('.md') || lower.endsWith('.txt')) {
      return Icons.article_outlined;
    }
    return Icons.description_outlined;
  }

  String _formatBytes(dynamic size) {
    final bytes = (size as num?)?.toInt() ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (files.isEmpty) return const SizedBox.shrink();

    return Material(
      color: tokens.surface.withValues(alpha: 0),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 240),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: tokens.overlay,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hint header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.alternate_email, size: 12, color: tokens.accent),
                  const SizedBox(width: 4),
                  Text(
                    'Collega file (@)',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tab / Invio per completare',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 9.5,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),
            // File items
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 2),
                shrinkWrap: true,
                itemCount: files.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
                itemBuilder: (context, index) {
                  final file = files[index];
                  final path = file['path']?.toString() ?? '';
                  final isSelected = index == selectedIndex;
                  final segments = path.replaceAll('\\', '/').split('/');
                  final fileName = segments.isNotEmpty ? segments.last : path;
                  final parentDir = segments.length > 1
                      ? segments.sublist(0, segments.length - 1).join('/')
                      : '';

                  return InkWell(
                    onTap: () => onSelect(path),
                    hoverColor: tokens.surface,
                    child: Container(
                      color: isSelected
                          ? tokens.accent.withValues(alpha: 0.12)
                          : tokens.surface.withValues(alpha: 0),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            _getFileIcon(path),
                            size: 14,
                            color: isSelected ? tokens.accent : tokens.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  fileName,
                                  style: TextStyle(
                                    color: isSelected ? tokens.accent : tokens.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                ),
                                if (parentDir.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      parentDir,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatBytes(file['sizeBytes']),
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10,
                              fontFamily: tokens.monoFontFamily,
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
        ),
      ),
    );
  }
}

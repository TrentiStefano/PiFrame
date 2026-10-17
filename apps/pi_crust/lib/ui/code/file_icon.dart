import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

/// Renders a distinctive, colorful file/folder icon based on file type and
/// Catppuccin semantic palette colors, matching the VS Code experience.
class FileIcon extends StatelessWidget {
  final String path;
  final double size;
  final bool isDirectory;
  final bool isExpanded;

  const FileIcon({
    super.key,
    required this.path,
    this.size = 15,
    this.isDirectory = false,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (isDirectory) {
      return Icon(
        isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
        size: size,
        color: tokens.warning,
      );
    }

    final lower = path.toLowerCase();
    IconData icon = Icons.insert_drive_file_outlined;
    Color color = tokens.textMuted;

    if (lower.endsWith('.dart')) {
      icon = Icons.flutter_dash;
      color = tokens.info;
    } else if (lower.endsWith('.json')) {
      icon = Icons.data_object;
      color = tokens.syntaxType;
    } else if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      icon = Icons.settings_outlined;
      color = tokens.danger;
    } else if (lower.endsWith('.ts') || lower.endsWith('.tsx')) {
      icon = Icons.code;
      color = tokens.info;
    } else if (lower.endsWith('.js') ||
        lower.endsWith('.jsx') ||
        lower.endsWith('.mjs') ||
        lower.endsWith('.cjs')) {
      icon = Icons.javascript;
      color = tokens.warning;
    } else if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      icon = Icons.article_outlined;
      color = tokens.info;
    } else if (lower.endsWith('.lock')) {
      icon = Icons.lock_outline;
      color = tokens.textMuted;
    } else if (lower.contains('.git')) {
      icon = Icons.merge_type;
      color = tokens.danger;
    } else if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      icon = Icons.html;
      color = tokens.syntaxNumber;
    } else if (lower.endsWith('.css') ||
        lower.endsWith('.scss') ||
        lower.endsWith('.sass') ||
        lower.endsWith('.less')) {
      icon = Icons.style_outlined;
      color = tokens.accent;
    } else if (lower.endsWith('.sh') ||
        lower.endsWith('.bash') ||
        lower.endsWith('.cmd') ||
        lower.endsWith('.bat') ||
        lower.endsWith('.ps1')) {
      icon = Icons.terminal_outlined;
      color = tokens.syntaxNumber;
    } else if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.ico')) {
      icon = Icons.image_outlined;
      color = tokens.success;
    }

    return Icon(icon, size: size, color: color);
  }
}

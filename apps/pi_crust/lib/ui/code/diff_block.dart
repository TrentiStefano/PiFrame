import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class DiffBlock extends StatefulWidget {
  final String diffText;
  final String? filename;

  const DiffBlock({
    super.key,
    required this.diffText,
    this.filename,
  });

  @override
  State<DiffBlock> createState() => _DiffBlockState();
}

class _DiffBlockState extends State<DiffBlock> {
  bool _copied = false;

  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.diffText));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lines = widget.diffText.split('\n');

    int additions = 0;
    int deletions = 0;
    for (final line in lines) {
      if (line.startsWith('+') && !line.startsWith('+++')) additions++;
      if (line.startsWith('-') && !line.startsWith('---')) deletions++;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: File/diff title, +/- stats, and Copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(tokens.radiusSm),
                topRight: Radius.circular(tokens.radiusSm),
              ),
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.difference_outlined, size: 14, color: tokens.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      widget.filename ?? 'DIFF',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontFamily: tokens.monoFontFamily,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (additions > 0)
                      Text(
                        '+$additions',
                        style: TextStyle(
                          color: tokens.diffAddedFg,
                          fontSize: 11,
                          fontFamily: tokens.monoFontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (additions > 0 && deletions > 0) const SizedBox(width: 6),
                    if (deletions > 0)
                      Text(
                        '-$deletions',
                        style: TextStyle(
                          color: tokens.diffRemovedFg,
                          fontSize: 11,
                          fontFamily: tokens.monoFontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                InkWell(
                  onTap: _copyToClipboard,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 12,
                          color: _copied ? tokens.success : tokens.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copiato!' : 'Copia',
                          style: TextStyle(
                            color: _copied ? tokens.success : tokens.textSecondary,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Diff lines
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: lines.map((line) => _buildDiffLine(line, tokens)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLine(String line, CrustTokens tokens) {
    Color? bg;
    Color fg = tokens.diffContextFg;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      bg = tokens.diffAddedBg;
      fg = tokens.diffAddedFg;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      bg = tokens.diffRemovedBg;
      fg = tokens.diffRemovedFg;
    } else if (line.startsWith('@@')) {
      bg = tokens.surfaceElevated;
      fg = tokens.accent;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text(
        line.isEmpty ? ' ' : line,
        style: TextStyle(
          color: fg,
          fontFamily: tokens.monoFontFamily,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}

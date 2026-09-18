import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

class CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const CodeBlock({
    super.key,
    required this.code,
    this.language,
  });

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
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
    final lang = widget.language?.trim().toLowerCase() ?? 'text';

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
          // Header: Language badge + Copy button
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
                Text(
                  lang.toUpperCase(),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11,
                    fontFamily: tokens.monoFontFamily,
                    fontWeight: FontWeight.bold,
                  ),
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

          // Code text area with horizontal scrolling
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              _highlightSyntax(widget.code, lang, tokens),
              style: TextStyle(
                fontFamily: tokens.monoFontFamily,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _highlightSyntax(String text, String lang, CrustTokens tokens) {
    // Fast regex-based tokenizer adhering strictly to CrustTokens.syntax tokens
    final spans = <TextSpan>[];

    final keywordRegex = RegExp(
        r'\b(async|await|break|case|catch|class|const|continue|default|do|else|enum|export|extends|false|final|finally|for|function|if|implements|import|in|interface|is|let|new|null|package|private|protected|public|return|static|super|switch|this|throw|true|try|typedef|var|void|while|with|yield)\b');
    final stringRegex = RegExp(r'''(['"`])(?:(?!\1)[^\\]|\\.)*\1''');
    final numberRegex = RegExp(r'\b\d+(\.\d+)?\b');
    final commentRegex = RegExp(r'(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)');

    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      final matches = <_SyntaxMatch>[];
      for (final m in commentRegex.allMatches(line)) {
        matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxComment));
      }
      for (final m in stringRegex.allMatches(line)) {
        matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxString));
      }
      for (final m in keywordRegex.allMatches(line)) {
        matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxKeyword));
      }
      for (final m in numberRegex.allMatches(line)) {
        matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxNumber));
      }

      // Sort by start index
      matches.sort((a, b) => a.start.compareTo(b.start));

      // Resolve non-overlapping matches
      int lastEnd = 0;
      for (final match in matches) {
        if (match.start < lastEnd) continue; // skip overlap
        if (match.start > lastEnd) {
          spans.add(TextSpan(
            text: line.substring(lastEnd, match.start),
            style: TextStyle(color: tokens.textPrimary),
          ));
        }
        spans.add(TextSpan(
          text: line.substring(match.start, match.end),
          style: TextStyle(color: match.color),
        ));
        lastEnd = match.end;
      }

      if (lastEnd < line.length) {
        spans.add(TextSpan(
          text: line.substring(lastEnd),
          style: TextStyle(color: tokens.textPrimary),
        ));
      }

      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }
}

class _SyntaxMatch {
  final int start;
  final int end;
  final Color color;
  _SyntaxMatch(this.start, this.end, this.color);
}

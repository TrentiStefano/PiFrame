import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../ui/code/code_block.dart';
import '../../ui/code/diff_block.dart';

class RichContent extends StatelessWidget {
  final String text;

  const RichContent({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final segments = _parseSegments(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((seg) {
        if (seg is _CodeSegment) {
          if (seg.language == 'diff') {
            return DiffBlock(diffText: seg.code);
          }
          return CodeBlock(code: seg.code, language: seg.language);
        } else if (seg is _TextSegment) {
          return _buildMarkdownText(seg.content, tokens);
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  List<_Segment> _parseSegments(String raw) {
    final segments = <_Segment>[];
    final normalized = raw.replaceAll('\r\n', '\n');
    final fenceRegex = RegExp(r'```([a-zA-Z0-9_\-\+]*)\n([\s\S]*?)```');

    int lastIndex = 0;
    for (final match in fenceRegex.allMatches(normalized)) {
      if (match.start > lastIndex) {
        final textPart = normalized.substring(lastIndex, match.start).trim();
        if (textPart.isNotEmpty) {
          segments.add(_TextSegment(textPart));
        }
      }

      final lang = match.group(1);
      final code = match.group(2) ?? '';
      segments.add(_CodeSegment(code: code, language: lang));
      lastIndex = match.end;
    }

    if (lastIndex < normalized.length) {
      final remaining = normalized.substring(lastIndex).trim();
      if (remaining.isNotEmpty) {
        segments.add(_TextSegment(remaining));
      }
    }

    if (segments.isEmpty && normalized.isNotEmpty) {
      segments.add(_TextSegment(normalized));
    }

    return segments;
  }

  Widget _buildMarkdownText(String text, CrustTokens tokens) {
    final rawLines = text.replaceAll('\r\n', '\n').split('\n');
    final widgets = <Widget>[];
    final currentPara = StringBuffer();

    void flushPara() {
      if (currentPara.isNotEmpty) {
        final content = currentPara.toString().trim();
        if (content.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText.rich(
              _parseInlineSpans(content, tokens),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ));
        }
        currentPara.clear();
      }
    }

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ') || trimmed.startsWith('## ') || trimmed.startsWith('### ')) {
        flushPara();
        if (trimmed.startsWith('### ')) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: SelectableText(
              trimmed.substring(4),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ));
        } else if (trimmed.startsWith('## ')) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: SelectableText(
              trimmed.substring(3),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ));
        } else if (trimmed.startsWith('# ')) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: SelectableText(
              trimmed.substring(2),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ));
        }
      } else if (trimmed.isEmpty) {
        flushPara();
      } else {
        if (currentPara.isNotEmpty) currentPara.write('\n');
        currentPara.write(line);
      }
    }
    flushPara();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  TextSpan _parseInlineSpans(String text, CrustTokens tokens) {
    final spans = <InlineSpan>[];
    final inlineCodeRegex = RegExp(r'`([^`]+)`');
    final boldRegex = RegExp(r'\*\*([^*]+)\*\*');

    final lines = text.split('\n');
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];

      final matches = <_InlineMatch>[];
      for (final m in inlineCodeRegex.allMatches(line)) {
        matches.add(_InlineMatch(m.start, m.end, m.group(1)!, _InlineType.code));
      }
      for (final m in boldRegex.allMatches(line)) {
        matches.add(_InlineMatch(m.start, m.end, m.group(1)!, _InlineType.bold));
      }
      matches.sort((a, b) => a.start.compareTo(b.start));

      int lastEnd = 0;
      for (final m in matches) {
        if (m.start < lastEnd) continue;
        if (m.start > lastEnd) {
          spans.add(TextSpan(text: line.substring(lastEnd, m.start)));
        }
        if (m.type == _InlineType.code) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm * 0.6),
                border: Border.all(color: tokens.border, width: 1),
              ),
              child: Text(
                m.text,
                style: TextStyle(
                  color: tokens.accent,
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 12,
                ),
              ),
            ),
          ));
        } else if (m.type == _InlineType.bold) {
          spans.add(TextSpan(
            text: m.text,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ));
        }
        lastEnd = m.end;
      }

      if (lastEnd < line.length) {
        spans.add(TextSpan(text: line.substring(lastEnd)));
      }

      if (l < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }
}

enum _InlineType { code, bold }

class _InlineMatch {
  final int start;
  final int end;
  final String text;
  final _InlineType type;
  _InlineMatch(this.start, this.end, this.text, this.type);
}

abstract class _Segment {}

class _TextSegment extends _Segment {
  final String content;
  _TextSegment(this.content);
}

class _CodeSegment extends _Segment {
  final String code;
  final String? language;
  _CodeSegment({required this.code, this.language});
}

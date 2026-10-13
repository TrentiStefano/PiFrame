import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'syntax_highlighter.dart';

class CodeEditorController extends TextEditingController {
  String? filePath;
  CrustTokens tokens;
  String searchQuery = '';
  bool caseSensitive = false;
  int currentMatchIndex = 0;

  CodeEditorController({
    super.text,
    this.filePath,
    required this.tokens,
  });

  List<TextRange> findMatches() {
    if (searchQuery.isEmpty || text.isEmpty) return const [];
    final matches = <TextRange>[];
    final pattern = caseSensitive ? searchQuery : searchQuery.toLowerCase();
    final source = caseSensitive ? text : text.toLowerCase();

    var startIndex = 0;
    while (startIndex < source.length) {
      final index = source.indexOf(pattern, startIndex);
      if (index == -1) break;
      matches.add(TextRange(start: index, end: index + pattern.length));
      startIndex = index + pattern.length;
    }
    return matches;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return const TextSpan();

    final baseStyle = style ??
        TextStyle(
          fontFamily: tokens.monoFontFamily,
          fontSize: 12,
          color: tokens.textPrimary,
        );

    final lang = SyntaxHighlighter.inferLanguage(filePath);
    final isCode = lang != 'text' && lang.isNotEmpty;
    final matches = findMatches();

    // If neither code highlighting nor search matches apply, return plain styled text.
    if (!isCode && matches.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final lines = text.split('\n');
    final allSpans = <InlineSpan>[];
    var globalOffset = 0;

    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      final lineStart = globalOffset;
      final lineEnd = lineStart + line.length;

      // Base line spans from syntax highlighter if code, else plain text
      final lineSpans = isCode
          ? SyntaxHighlighter.highlightLine(
              line,
              lang,
              tokens,
              defaultColor: baseStyle.color,
            )
          : [TextSpan(text: line, style: baseStyle)];

      if (matches.isEmpty) {
        allSpans.addAll(lineSpans);
      } else {
        // Overlay search matches that intersect this line
        final intersectingMatches = <({int start, int end, bool isCurrent})>[];
        for (var mIdx = 0; mIdx < matches.length; mIdx++) {
          final m = matches[mIdx];
          if (m.end > lineStart && m.start < lineEnd) {
            final relStart = (m.start - lineStart).clamp(0, line.length);
            final relEnd = (m.end - lineStart).clamp(0, line.length);
            if (relStart < relEnd) {
              intersectingMatches.add((
                start: relStart,
                end: relEnd,
                isCurrent: mIdx == currentMatchIndex,
              ));
            }
          }
        }

        if (intersectingMatches.isEmpty) {
          allSpans.addAll(lineSpans);
        } else {
          allSpans.addAll(_applySearchHighlightsToLine(
            line,
            lineSpans,
            intersectingMatches,
            baseStyle,
          ));
        }
      }

      if (lineIdx < lines.length - 1) {
        allSpans.add(const TextSpan(text: '\n'));
      }
      globalOffset += line.length + 1; // +1 for the '\n'
    }

    return TextSpan(style: baseStyle, children: allSpans);
  }

  List<InlineSpan> _applySearchHighlightsToLine(
    String line,
    List<InlineSpan> originalSpans,
    List<({int start, int end, bool isCurrent})> lineMatches,
    TextStyle baseStyle,
  ) {
    final result = <InlineSpan>[];
    var currentOffset = 0;

    // Flatten original spans into characters with their styling
    final charStyles = List<TextStyle?>.filled(line.length, null);
    var charIdx = 0;
    for (final span in originalSpans) {
      if (span is TextSpan && span.text != null) {
        final spanText = span.text!;
        final spanStyle = span.style;
        for (var i = 0; i < spanText.length && charIdx < line.length; i++) {
          charStyles[charIdx] = spanStyle;
          charIdx++;
        }
      }
    }

    for (final m in lineMatches) {
      // Span before match
      if (m.start > currentOffset) {
        result.addAll(_reconstructSpans(
          line,
          currentOffset,
          m.start,
          charStyles,
          baseStyle,
        ));
      }

      // Matched segment
      final matchText = line.substring(m.start, m.end);
      final matchHighlightBg = m.isCurrent
          ? tokens.accent
          : tokens.warning.withValues(alpha: 0.35);
      final matchTextColor = m.isCurrent
          ? tokens.background
          : tokens.textPrimary;

      result.add(
        TextSpan(
          text: matchText,
          style: TextStyle(
            backgroundColor: matchHighlightBg,
            color: matchTextColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      currentOffset = m.end;
    }

    // Remainder of line after last match
    if (currentOffset < line.length) {
      result.addAll(_reconstructSpans(
        line,
        currentOffset,
        line.length,
        charStyles,
        baseStyle,
      ));
    }

    return result;
  }

  List<InlineSpan> _reconstructSpans(
    String line,
    int start,
    int end,
    List<TextStyle?> charStyles,
    TextStyle baseStyle,
  ) {
    if (start >= end) return const [];
    final spans = <InlineSpan>[];
    var segStart = start;
    var currentStyle = charStyles[start];

    for (var i = start + 1; i < end; i++) {
      if (charStyles[i] != currentStyle) {
        spans.add(TextSpan(
          text: line.substring(segStart, i),
          style: currentStyle ?? baseStyle,
        ));
        segStart = i;
        currentStyle = charStyles[i];
      }
    }

    spans.add(TextSpan(
      text: line.substring(segStart, end),
      style: currentStyle ?? baseStyle,
    ));

    return spans;
  }
}

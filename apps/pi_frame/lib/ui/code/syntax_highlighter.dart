import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class SyntaxHighlighter {
  static String inferLanguage(String? filename) {
    if (filename == null || filename.isEmpty) return 'text';
    final dot = filename.lastIndexOf('.');
    if (dot == -1) return 'text';
    final ext = filename.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'dart':
        return 'dart';
      case 'ts':
      case 'tsx':
        return 'typescript';
      case 'js':
      case 'jsx':
      case 'mjs':
        return 'javascript';
      case 'py':
        return 'python';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'sh':
      case 'bash':
      case 'zsh':
        return 'bash';
      case 'md':
      case 'markdown':
        return 'markdown';
      case 'rs':
        return 'rust';
      case 'go':
        return 'go';
      case 'html':
        return 'html';
      case 'css':
      case 'scss':
        return 'css';
      default:
        return ext;
    }
  }

  static TextSpan highlight(String text, String lang, FrameTokens tokens) {
    final lines = text.split('\n');
    final allSpans = <InlineSpan>[];

    for (var i = 0; i < lines.length; i++) {
      allSpans.addAll(highlightLine(lines[i], lang, tokens));
      if (i < lines.length - 1) {
        allSpans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: allSpans);
  }

  static final RegExp _keywordRegex = RegExp(
    r'\b(async|await|break|case|catch|class|const|continue|default|def|do|else|enum|export|extends|false|final|finally|fn|for|from|function|if|implements|import|in|interface|is|let|match|mut|new|nil|None|null|package|private|protected|pub|public|return|self|static|struct|super|switch|this|throw|True|true|try|type|typedef|var|void|while|with|yield)\b',
  );
  static final RegExp _stringRegex = RegExp(r'''(['"`])(?:(?!\1)[^\\]|\\.)*\1''');
  static final RegExp _numberRegex = RegExp(r'\b\d+(\.\d+)?\b');
  static final RegExp _commentRegex = RegExp(r'(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)');
  static final RegExp _typeRegex = RegExp(r'\b[A-Z][a-zA-Z0-9_]*\b');

  static List<InlineSpan> highlightLine(
    String line,
    String lang,
    FrameTokens tokens, {
    Color? defaultColor,
  }) {
    if (line.isEmpty) return [const TextSpan(text: '')];

    final baseFg = defaultColor ?? tokens.textPrimary;

    final matches = <_SyntaxMatch>[];

    for (final m in _commentRegex.allMatches(line)) {
      matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxComment));
    }
    for (final m in _stringRegex.allMatches(line)) {
      matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxString));
    }
    for (final m in _keywordRegex.allMatches(line)) {
      matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxKeyword));
    }
    for (final m in _typeRegex.allMatches(line)) {
      matches.add(_SyntaxMatch(m.start, m.end, tokens.accent));
    }
    for (final m in _numberRegex.allMatches(line)) {
      matches.add(_SyntaxMatch(m.start, m.end, tokens.syntaxNumber));
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start < lastEnd) continue; // skip overlap
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: line.substring(lastEnd, match.start),
            style: TextStyle(color: baseFg),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: line.substring(match.start, match.end),
          style: TextStyle(
            color: match.color,
            fontWeight: match.color == tokens.syntaxKeyword
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.add(
        TextSpan(
          text: line.substring(lastEnd),
          style: TextStyle(color: baseFg),
        ),
      );
    }

    return spans;
  }
}

class _SyntaxMatch {
  final int start;
  final int end;
  final Color color;
  _SyntaxMatch(this.start, this.end, this.color);
}

import 'package:flutter/material.dart';

/// Measures each logical line of a code buffer, so the line-number gutter and
/// the current-line band line up with the editor text, including lines that
/// soft-wrap. Heights are cached per line text and reset when the style or the
/// wrap width changes.
class CodeLineLayout {
  static const int _maxCachedLines = 5000;

  final Map<String, double> _heights = <String, double>{};
  String? _signature;

  /// Height in px of every line in [lines], laid out with [style]. A null
  /// [maxWidth] means no soft wrap, so every line is exactly one line high.
  ///
  /// [textScaler] must be the one the editor renders with (the
  /// `MediaQuery` text scaler), or the measured lines drift from the text.
  List<double> lineHeights(
    List<String> lines,
    TextStyle style,
    double? maxWidth, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final single = _singleLineHeight(style, textScaler);
    if (maxWidth == null) {
      return List<double>.filled(lines.length, single);
    }
    final signature =
        '${style.fontFamily}|${style.fontSize}|${style.height}|$maxWidth|'
        '${textScaler.scale(10)}';
    if (signature != _signature || _heights.length > _maxCachedLines) {
      _heights.clear();
      _signature = signature;
    }
    return [for (final line in lines) _heights.putIfAbsent(line, () => _measure(line, style, maxWidth, textScaler))];
  }

  /// Width in px of the widest line. Only exact for monospace styles, which
  /// is what the code editor uses: the longest line is the widest one.
  double widestLineWidth(List<String> lines, TextStyle style, {TextScaler textScaler = TextScaler.noScaling}) {
    var longest = '';
    for (final line in lines) {
      if (line.length > longest.length) longest = line;
    }
    if (longest.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: longest, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _measure(String line, TextStyle style, double maxWidth, TextScaler textScaler) {
    if (line.isEmpty) return _singleLineHeight(style, textScaler);
    final painter = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth < 1 ? 1 : maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  double _singleLineHeight(TextStyle style, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

/// Paints 1-based line numbers in the gutter, right-aligned, one per logical
/// line at the y position of that line. Only lines inside the visible window
/// are painted; [scroll] repaints the gutter as the editor scrolls.
class CodeLineGutterPainter extends CustomPainter {
  CodeLineGutterPainter({
    required this.lineCount,
    required this.tops,
    required this.heights,
    required this.caretLine,
    required this.numberStyle,
    required this.currentStyle,
    required this.scroll,
    required this.viewportHeight,
    required this.padding,
    required this.rightInset,
    this.textScaler = TextScaler.noScaling,
  }) : super(repaint: scroll);

  /// Text scaler the editor text renders with, so numbers match the lines.
  final TextScaler textScaler;

  /// Number of logical lines; one number is painted for each.
  final int lineCount;

  /// Top y of each line, measured from the top of the editor content.
  final List<double> tops;

  /// Rendered height of each line.
  final List<double> heights;

  /// 0-based index of the line that holds the caret.
  final int caretLine;

  final TextStyle numberStyle;
  final TextStyle currentStyle;
  final ScrollController scroll;
  final double viewportHeight;
  final double padding;
  final double rightInset;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    final bottom = offset + viewportHeight;
    for (var i = 0; i < lineCount && i < tops.length; i++) {
      final y = tops[i];
      final height = i < heights.length ? heights[i] : 0.0;
      if (y + height < offset) continue;
      if (y > bottom) break;
      final painter = TextPainter(
        text: TextSpan(text: '${i + 1}', style: i == caretLine ? currentStyle : numberStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      painter.paint(canvas, Offset(size.width - rightInset - painter.width, y));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant CodeLineGutterPainter oldDelegate) =>
      oldDelegate.lineCount != lineCount ||
      !identical(oldDelegate.tops, tops) ||
      oldDelegate.caretLine != caretLine ||
      oldDelegate.viewportHeight != viewportHeight ||
      oldDelegate.numberStyle != numberStyle ||
      oldDelegate.currentStyle != currentStyle ||
      oldDelegate.textScaler != textScaler;
}

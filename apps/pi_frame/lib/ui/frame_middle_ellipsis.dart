import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One line of text that truncates in the middle, keeping the last path
/// segment whole: `C:\Repos\PiFrame\…\apps\main.dart`.
///
/// The head is cut first, so the start of the path and the file or folder
/// name stay readable. Text that fits is shown unchanged. A [Tooltip] with the
/// full text is attached only when the text is actually truncated.
///
/// Text with no separator falls back to an end ellipsis. When the last segment
/// alone does not fit, that segment is cut at the end instead.
class FrameMiddleEllipsis extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FrameMiddleEllipsis({super.key, required this.text, this.style});

  static const String _ellipsis = '…';

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    bool fits(String candidate, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(text: candidate, style: effective),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width <= maxWidth;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final label = _label(effective);
        if (!constraints.hasBoundedWidth) {
          return label(text);
        }
        final maxWidth = constraints.maxWidth;
        final shown = middleEllipsize(
          text,
          (candidate) => fits(candidate, maxWidth),
        );
        if (shown == text) {
          return label(text);
        }
        return Tooltip(message: text, child: label(shown));
      },
    );
  }

  Widget Function(String) _label(TextStyle style) {
    return (String shown) => Text(
      shown,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      semanticsLabel: text,
      style: style,
    );
  }

  /// Returns [text] when [fits] accepts it, otherwise the longest middle
  /// truncation that [fits] accepts. Exposed for unit tests.
  @visibleForTesting
  static String middleEllipsize(String text, bool Function(String) fits) {
    if (fits(text)) return text;

    final separator = math.max(text.lastIndexOf('/'), text.lastIndexOf('\\'));
    if (separator < 0 || separator == text.length - 1) {
      return _endEllipsize(text, fits);
    }

    final head = text.substring(0, separator);
    final tail = text.substring(separator);
    String candidate(int keep) => '${head.substring(0, keep)}$_ellipsis$tail';

    if (!fits(candidate(0))) {
      // The last segment alone does not fit next to the ellipsis, so keep its
      // start and cut the end instead.
      return _endEllipsize(tail.substring(1), fits);
    }

    var low = 0;
    var high = head.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits(candidate(mid))) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return candidate(low);
  }

  static String _endEllipsize(String text, bool Function(String) fits) {
    var low = 0;
    var high = text.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits('${text.substring(0, mid)}$_ellipsis')) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return '${text.substring(0, low)}$_ellipsis';
  }
}

import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Lit bars (0 to 4) for a thinking level, so the icon shows how much thinking is on.
int thinkingLevelSteps(String? level) => switch ((level ?? 'medium').toLowerCase()) {
  'off' => 0,
  'minimal' || 'low' => 1,
  'medium' => 2,
  'high' => 3,
  'xhigh' || 'max' => 4,
  _ => 2,
};

/// Four rising bars, the first [thinkingLevelSteps] of them lit. It replaces the same bolt icon
/// that every level used to share (plan 4.4, review 6.7 item 3).
class ThinkingLevelBars extends StatelessWidget {
  const ThinkingLevelBars({super.key, required this.level, required this.litColor});

  final String? level;
  final Color litColor;

  static const double _barWidth = 2;
  static const double _gap = 1.5;
  static const List<double> _heights = [4, 7, 10, 13];

  /// Width of the whole icon, for layout budgets.
  static const double width = 4 * _barWidth + 3 * _gap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final lit = thinkingLevelSteps(level);
    return SizedBox(
      width: width,
      height: _heights.last,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _heights.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Container(
              key: ValueKey('thinking-bar-$i-${i < lit ? 'lit' : 'dim'}'),
              width: _barWidth,
              height: _heights[i],
              decoration: BoxDecoration(
                color: i < lit ? litColor : tokens.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(_barWidth / 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

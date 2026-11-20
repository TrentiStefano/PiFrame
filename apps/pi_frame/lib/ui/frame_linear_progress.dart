import 'package:flutter/material.dart';

import 'motion.dart';

/// Linear progress bar that never loops under reduced motion.
///
/// With a known [value] it shows that fraction in both modes. With no value
/// (indeterminate work) it animates normally, and under reduced motion it is
/// a full static bar in [color], so nothing moves on screen.
class FrameLinearProgress extends StatelessWidget {
  final double? value;
  final Color color;
  final Color? backgroundColor;
  final double minHeight;

  const FrameLinearProgress({super.key, required this.color, this.value, this.backgroundColor, this.minHeight = 4});

  @override
  Widget build(BuildContext context) {
    if (FrameMotion.reduced(context) && value == null) {
      return SizedBox(
        height: minHeight,
        width: double.infinity,
        child: ColoredBox(color: color),
      );
    }
    return LinearProgressIndicator(value: value, color: color, backgroundColor: backgroundColor, minHeight: minHeight);
  }
}

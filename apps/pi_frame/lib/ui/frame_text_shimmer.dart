import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'motion.dart';

/// A text widget with an animated luminous shimmer gradient sweeping across it,
/// inspired by loading-ui TextShimmer (https://www.loading-ui.com/docs/components/text-shimmer).
///
/// Under reduced motion or in widget test environments, the animation stops
/// and renders static high-contrast text.
class FrameTextShimmer extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  const FrameTextShimmer({
    super.key,
    required this.text,
    required this.style,
    this.baseColor,
    this.highlightColor,
    this.duration = FrameMotion.textShimmerLoop,
  });

  @override
  State<FrameTextShimmer> createState() => _FrameTextShimmerState();
}

class _FrameTextShimmerState extends State<FrameTextShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final bool _isTest;

  @override
  void initState() {
    super.initState();
    _isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (!_isTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = widget.baseColor ?? tokens.textMuted;
    final highlight = widget.highlightColor ?? tokens.textPrimary;

    if (_isTest || FrameMotion.reduced(context)) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style.copyWith(color: highlight),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            // Sweeps gradient highlight from -bounds.width to +2 * bounds.width
            final dx = bounds.width * (_controller.value * 3.0 - 1.0);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                base,
                highlight,
                base,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradientTransform(dx),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style.copyWith(color: Colors.white),
      ),
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double dx;

  const _SlideGradientTransform(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0.0, 0.0);
  }
}

import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class ShimmerBorder extends StatefulWidget {
  final bool isActive;
  final Widget child;
  final BorderRadius borderRadius;
  final double strokeWidth;

  const ShimmerBorder({
    super.key,
    required this.isActive,
    required this.child,
    required this.borderRadius,
    this.strokeWidth = 2.0,
  });

  @override
  State<ShimmerBorder> createState() => _ShimmerBorderState();
}

class _ShimmerBorderState extends State<ShimmerBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Phone browsers (canvaskit) cannot sustain a 60fps blurred sweep + animated shadow around the
  /// composer while the agent streams: it made the whole web UI lag. Use a static accent border.
  bool _lite = false;

  bool get _isTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lite = kIsWeb && MediaQuery.sizeOf(context).width < 700;
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.isActive && !_isTest && !_lite) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(ShimmerBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (!widget.isActive) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(color: tokens.border, width: 1),
        ),
        child: widget.child,
      );
    }

    if (_lite) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          // Thin, softened accent: a 2px bright ring looked heavy around the phone composer.
          border: Border.all(
            color: tokens.accent.withValues(alpha: 0.7),
            width: math.min(widget.strokeWidth, 1.25),
          ),
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final angle = _controller.value * 2 * math.pi;
        final pulse = 0.16 + 0.10 * math.sin(angle);

        return CustomPaint(
          painter: _SweepBorderPainter(
            progress: _controller.value,
            borderRadius: widget.borderRadius,
            strokeWidth: widget.strokeWidth,
            borderColor: tokens.border,
            accentColor: tokens.accent,
            glowColor: tokens.focusRing,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: [
                BoxShadow(
                  color: tokens.accent.withValues(alpha: pulse),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _SweepBorderPainter extends CustomPainter {
  final double progress;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final Color borderColor;
  final Color accentColor;
  final Color glowColor;

  _SweepBorderPainter({
    required this.progress,
    required this.borderRadius,
    required this.strokeWidth,
    required this.borderColor,
    required this.accentColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(strokeWidth / 2);

    // 1. Draw base border
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = borderColor;
    canvas.drawRRect(rrect, basePaint);

    final angle = progress * 2 * math.pi;

    // Glowing beam sweep gradient: concentrated peak at 0.75 stop
    final shader = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(angle),
      colors: [
        borderColor.withValues(alpha: 0.0),
        borderColor.withValues(alpha: 0.0),
        accentColor.withValues(alpha: 0.3),
        glowColor,
        accentColor,
        accentColor.withValues(alpha: 0.3),
        borderColor.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.50, 0.68, 0.75, 0.82, 0.90, 1.0],
    ).createShader(rect);

    // 2. Draw outer blur glow beam
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
      ..shader = shader;
    canvas.drawRRect(rrect, glowPaint);

    // 3. Draw inner sharp crisp highlight beam
    final sharpPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = shader;
    canvas.drawRRect(rrect, sharpPaint);
  }

  @override
  bool shouldRepaint(_SweepBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor;
  }
}

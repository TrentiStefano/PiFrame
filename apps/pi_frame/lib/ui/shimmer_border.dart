import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Accent ring around an active composer.
///
/// Normal motion: one light beam travels around the ring, accelerates and
/// settles, then the ring rests for the remainder of the cycle. The beam fades
/// in and out, so the ring is quiet between passes.
///
/// Reduced motion, phone-web, and tests: a static accent ring with no loop.
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

/// Fraction of each cycle spent travelling; the rest is the resting ring.
const double _sweepFraction = 0.6;

class _ShimmerBorderState extends State<ShimmerBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Phone browsers (canvaskit) cannot sustain a 60fps blurred sweep + animated shadow around the
  /// composer while the agent streams: it made the whole web UI lag. Use a static accent border.
  bool _lite = false;

  /// The OS or the app's Reduce motion setting asks for no movement.
  bool _reduced = false;

  bool get _isTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lite = kIsWeb && MediaQuery.sizeOf(context).width < 700;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  bool get _animates => widget.isActive && !_isTest && !_lite && !_reduced;

  void _syncAnimation() {
    if (_animates) {
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

    if (_lite || _reduced) {
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
        final cycle = _controller.value;
        final sweep = (cycle / _sweepFraction).clamp(0.0, 1.0);
        final eased = Curves.easeInOutCubic.transform(sweep);
        // Beam strength rises and falls across the pass, so it never snaps on or off.
        final intensity = math.sin(math.pi * sweep);
        final glow = 0.10 * intensity;

        return CustomPaint(
          painter: _SweepBorderPainter(
            progress: eased,
            intensity: intensity,
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
                if (glow > 0)
                  BoxShadow(
                    color: tokens.accent.withValues(alpha: glow),
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
  final double intensity;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final Color borderColor;
  final Color accentColor;
  final Color glowColor;

  _SweepBorderPainter({
    required this.progress,
    required this.intensity,
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

    // 1. Base border, always visible.
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = borderColor;
    canvas.drawRRect(rrect, basePaint);

    if (intensity <= 0.001) return;

    final angle = progress * 2 * math.pi;
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

    // 2 & 3. Beam: blurred halo and crisp core, faded by [intensity] through a layer.
    canvas.saveLayer(
      rect,
      Paint()..color = Color.fromRGBO(0, 0, 0, intensity),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
        ..shader = shader,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor;
  }
}

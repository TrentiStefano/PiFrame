import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Accent ring around an active composer.
///
/// Normal motion: an animated light beam sweeps around the ring, with a visible
/// atmospheric glow halo that surrounds the composer box while the agent is active.
///
/// Reduced motion, phone-web, and [animate] false (the caller's test-environment check): a static accent ring with no loop.
class ShimmerBorder extends StatefulWidget {
  final bool isActive;
  final Widget child;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final bool animate;

  const ShimmerBorder({
    super.key,
    required this.isActive,
    required this.child,
    required this.borderRadius,
    this.strokeWidth = 2.0,
    this.animate = true,
  });

  @override
  State<ShimmerBorder> createState() => _ShimmerBorderState();
}

class _ShimmerBorderState extends State<ShimmerBorder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Phone browsers (canvaskit) cannot sustain a 60fps blurred sweep + animated shadow around the
  /// composer while the agent streams: it made the whole web UI lag. Use a static accent border.
  bool _lite = false;

  /// The OS or the app's Reduce motion setting asks for no movement.
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: FrameMotionTokens.shimmerLoop);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lite = kIsWeb && MediaQuery.sizeOf(context).width < 700;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  bool get _animates => widget.isActive && widget.animate && !_lite && !_reduced;

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
          border: Border.all(color: tokens.accent.withValues(alpha: 0.7), width: math.min(widget.strokeWidth, 1.25)),
        ),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final cycle = _controller.value;
        final angle = cycle * 2 * math.pi;
        final intensity = 0.80 + 0.20 * math.sin(angle);

        return CustomPaint(
          painter: _ShimmerOuterGlowPainter(
            progress: cycle,
            intensity: intensity,
            borderRadius: widget.borderRadius,
            strokeWidth: widget.strokeWidth,
            accentColor: tokens.accent,
            glowColor: tokens.focusRing,
          ),
          foregroundPainter: _ShimmerBeamPainter(
            progress: cycle,
            intensity: intensity,
            borderRadius: widget.borderRadius,
            strokeWidth: widget.strokeWidth,
            borderColor: tokens.border,
            accentColor: tokens.accent,
            glowColor: tokens.focusRing,
          ),
          child: child,
        );
      },
    );
  }
}

class _ShimmerOuterGlowPainter extends CustomPainter {
  final double progress;
  final double intensity;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final Color accentColor;
  final Color glowColor;

  _ShimmerOuterGlowPainter({
    required this.progress,
    required this.intensity,
    required this.borderRadius,
    required this.strokeWidth,
    required this.accentColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // 1. Soft atmospheric ambient glow that pulses gently with activity
    final ambientAlpha = (0.16 * intensity).clamp(0.0, 1.0);
    final ambientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
      ..color = accentColor.withValues(alpha: ambientAlpha);
    canvas.drawRRect(rrect, ambientPaint);

    // 2. Focused travelling halo following the beam head
    final angle = progress * 2 * math.pi;
    final haloShader = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(angle),
      colors: [
        accentColor.withValues(alpha: 0.0),
        accentColor.withValues(alpha: 0.0),
        accentColor.withValues(alpha: 0.25 * intensity),
        glowColor.withValues(alpha: 0.75 * intensity),
        accentColor.withValues(alpha: 0.50 * intensity),
        accentColor.withValues(alpha: 0.20 * intensity),
        accentColor.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.45, 0.65, 0.75, 0.85, 0.95, 1.0],
    ).createShader(rect);

    final beamGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
      ..shader = haloShader;
    canvas.drawRRect(rrect, beamGlowPaint);
  }

  @override
  bool shouldRepaint(_ShimmerOuterGlowPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor;
  }
}

class _ShimmerBeamPainter extends CustomPainter {
  final double progress;
  final double intensity;
  final BorderRadius borderRadius;
  final double strokeWidth;
  final Color borderColor;
  final Color accentColor;
  final Color glowColor;

  _ShimmerBeamPainter({
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

    // 1. Base border, always visible
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = borderColor;
    canvas.drawRRect(rrect, basePaint);

    final angle = progress * 2 * math.pi;
    final beamShader = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(angle),
      colors: [
        borderColor.withValues(alpha: 0.0),
        borderColor.withValues(alpha: 0.0),
        accentColor.withValues(alpha: 0.4 * intensity),
        glowColor.withValues(alpha: 1.0 * intensity),
        accentColor.withValues(alpha: 0.9 * intensity),
        accentColor.withValues(alpha: 0.4 * intensity),
        borderColor.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.50, 0.68, 0.75, 0.82, 0.90, 1.0],
    ).createShader(rect);

    // 2. Beam halo along the border
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
      ..shader = beamShader;
    canvas.drawRRect(rrect, haloPaint);

    // 3. Crisp travelling beam core
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = beamShader;
    canvas.drawRRect(rrect, corePaint);
  }

  @override
  bool shouldRepaint(_ShimmerBeamPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor;
  }
}

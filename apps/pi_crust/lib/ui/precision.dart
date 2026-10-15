import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

/// Pointer feedback does not delay or animate keyboard activation.
class PressFeedback extends StatefulWidget {
  final Widget child;
  const PressFeedback({super.key, required this.child});
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _pressed = false;
  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse ||
            event.kind == PointerDeviceKind.touch) {
          setState(() => _pressed = true);
        }
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _pressed && !MediaQuery.disableAnimationsOf(context) ? 0.97 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : tokens.pressDuration,
        curve: tokens.enterCurve,
        child: widget.child,
      ),
    );
  }
}

class _LaunchScope extends InheritedWidget {
  final Animation<double> progress;
  const _LaunchScope({required this.progress, required super.child});
  @override
  bool updateShouldNotify(_LaunchScope oldWidget) =>
      progress != oldWidget.progress;
}

/// A once-per-launch reveal. The application is visible and interactive from
/// the first frame; any pointer or keyboard input finishes the reveal at once.
class LaunchReveal extends StatefulWidget {
  final Widget child;
  const LaunchReveal({super.key, required this.child});
  @override
  State<LaunchReveal> createState() => _LaunchRevealState();
}

class _LaunchRevealState extends State<LaunchReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  bool _started = false;
  bool _startScheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      _started = true;
    } else if (!_started && !_startScheduled) {
      _startScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _started) return;
        _started = true;
        if (MediaQuery.disableAnimationsOf(context)) {
          _controller.value = 1;
        } else {
          _controller.forward();
        }
      });
    }
  }

  void _finish() {
    if (_controller.value < 1) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _controller.drive(
      CurveTween(curve: context.tokens.enterCurve),
    );
    return Listener(
      onPointerDown: (_) => _finish(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          _finish();
          return KeyEventResult.ignored;
        },
        child: _LaunchScope(
          progress: _controller,
          child: FadeTransition(
            key: const ValueKey('launch-opacity'),
            opacity: Tween<double>(begin: 0.82, end: 1).animate(progress),
            child: SlideTransition(
              key: const ValueKey('launch-transform'),
              position: Tween<Offset>(
                begin: const Offset(0, 0.006),
                end: Offset.zero,
              ).animate(progress),
              child: RepaintBoundary(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The official 3D pie slice Pi-Crust mark. Adapts to theme brightness,
/// with graceful fallback for headless tests without asset bindings.
class CrustMark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? crustColor;
  const CrustMark({super.key, this.size = 32, this.color, this.crustColor});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assetPath = isDark
        ? 'assets/branding/app_icon_dark_512.png'
        : 'assets/branding/app_icon_light_512.png';

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final cacheDim = (size * dpr).round();

    return Semantics(
      label: 'Pi-Crust',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          cacheWidth: cacheDim,
          cacheHeight: cacheDim,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) {
            final progress = context
                .dependOnInheritedWidgetOfExactType<_LaunchScope>()
                ?.progress;
            return SizedBox.square(
              dimension: size,
              child: CustomPaint(
                painter: _MarkPainter(
                  color ?? tokens.accent,
                  crustColor ?? tokens.borderStrong,
                  tokens.surface,
                  tokens.enterCurve,
                  progress,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  final Color crustColor;
  final Color surfaceColor;
  final Curve curve;
  final Animation<double>? progress;
  _MarkPainter(
    this.color,
    this.crustColor,
    this.surfaceColor,
    this.curve,
    this.progress,
  ) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 32, 32));

    final overallPhase = curve.transform((progress?.value ?? 1.0).clamp(0.0, 1.0));

    // 1. 12-lobed fluted pie crust seal rim
    final scallop = Path();
    const nCrimps = 12;
    const steps = nCrimps * 4;
    for (var i = 0; i < steps; i++) {
      final angle = (i * 2 * math.pi) / steps - (math.pi / 2);
      final wave = math.cos(nCrimps * angle);
      final r = 13.0 + 2.2 * (0.5 + 0.5 * wave);
      final px = 16.0 + r * math.cos(angle);
      final py = 16.0 + r * math.sin(angle);
      if (i == 0) {
        scallop.moveTo(px, py);
      } else {
        scallop.lineTo(px, py);
      }
    }
    scallop.close();

    canvas.drawPath(
      scallop,
      Paint()..color = crustColor.withValues(alpha: 0.15 + 0.85 * overallPhase),
    );

    // 2. Inner circular pastry well
    canvas.drawCircle(
      const Offset(16, 16),
      10.6,
      Paint()..color = surfaceColor,
    );
    canvas.drawCircle(
      const Offset(16, 16),
      10.6,
      Paint()
        ..color = crustColor.withValues(alpha: 0.45 * overallPhase)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // 3. Delicate score marks above and below
    final slitPaint = Paint()
      ..color = crustColor.withValues(alpha: 0.7 * overallPhase)
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;
    // Above
    canvas.drawLine(const Offset(14.5, 7.8), const Offset(14.8, 8.8), slitPaint);
    canvas.drawLine(const Offset(16.0, 7.5), const Offset(16.0, 8.6), slitPaint);
    canvas.drawLine(const Offset(17.5, 7.8), const Offset(17.2, 8.8), slitPaint);
    // Below
    canvas.drawLine(const Offset(14.5, 24.2), const Offset(14.8, 23.2), slitPaint);
    canvas.drawLine(const Offset(16.0, 24.5), const Offset(16.0, 23.4), slitPaint);
    canvas.drawLine(const Offset(17.5, 24.2), const Offset(17.2, 23.2), slitPaint);

    // 4. Official pi-coding-agent geometric mark
    // Center at (16, 16), 4x4 block unit = 3.25
    // P shape parts + i block
    const parts = [
      Rect.fromLTWH(9.5, 9.5, 3.25, 13.0),   // P stem
      Rect.fromLTWH(12.75, 9.5, 6.5, 3.25),  // P top bar
      Rect.fromLTWH(16.0, 12.75, 3.25, 3.25),// P right wall
      Rect.fromLTWH(12.75, 16.0, 3.25, 3.25),// P bottom loop
      Rect.fromLTWH(19.25, 16.0, 3.25, 6.5), // i block
    ];

    for (var i = 0; i < parts.length; i++) {
      final phase = curve.transform(
        (((progress?.value ?? 1) * 1.6) - (i * 0.12)).clamp(0.0, 1.0),
      );
      canvas.drawRect(
        parts[i].shift(Offset((1 - phase) * (i.isEven ? -6 : 6), 0)),
        Paint()..color = color.withValues(alpha: 0.15 + 0.85 * phase),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.color != color ||
      old.crustColor != crustColor ||
      old.surfaceColor != surfaceColor ||
      old.progress != progress ||
      old.curve != curve;
}

class BrandWordmark extends StatelessWidget {
  final double size;
  const BrandWordmark({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Text(
    'PI–CRUST',
    style: TextStyle(
      fontFamily: context.tokens.headingFontFamily,
      fontWeight: FontWeight.w700,
      fontSize: size,
      height: 1,
      letterSpacing: -0.4,
      color: context.tokens.textPrimary,
    ),
  );
}

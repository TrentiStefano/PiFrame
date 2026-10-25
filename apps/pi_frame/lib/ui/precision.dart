import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

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

/// The official PiFrame mark. Adapts to theme brightness,
/// with graceful fallback for headless tests without asset bindings.
class PiFrameMark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? frameColor;
  const PiFrameMark({super.key, this.size = 32, this.color, this.frameColor});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        tokens.background.computeLuminance() < 0.5;
    final assetPath = isDark
        ? 'assets/branding/app_icon_dark_512.png'
        : 'assets/branding/app_icon_light_512.png';

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final cacheDim = (size * dpr).round();

    return Semantics(
      label: 'PiFrame',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          assetPath,
          key: ValueKey(assetPath),
          gaplessPlayback: true,
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
                  tokens.danger,
                  tokens.warning,
                  frameColor ?? tokens.borderStrong,
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
  final Color blueColor;
  final Color coralColor;
  final Color amberColor;
  final Color frameColor;
  final Color surfaceColor;
  final Curve curve;
  final Animation<double>? progress;
  _MarkPainter(
    this.blueColor,
    this.coralColor,
    this.amberColor,
    this.frameColor,
    this.surfaceColor,
    this.curve,
    this.progress,
  ) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 32, 32));

    final overallPhase = curve.transform(
      (progress?.value ?? 1.0).clamp(0.0, 1.0),
    );

    // 1. Geometric PiFrame outer rounded frame
    final outerFrame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2, 2, 28, 28),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      outerFrame,
      Paint()
        ..color = frameColor.withValues(alpha: 0.15 + 0.85 * overallPhase)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 2. Inner surface background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.2, 3.2, 25.6, 25.6),
        const Radius.circular(5.5),
      ),
      Paint()..color = surfaceColor,
    );

    // 3. Official pi-coding-agent geometric mark
    // Center at (16, 16), 4x4 block unit = 3.25
    // P shape parts + i block with icon branding colors
    const parts = [
      Rect.fromLTWH(9.5, 9.5, 3.25, 13.0), // P stem (Blue)
      Rect.fromLTWH(12.75, 9.5, 6.5, 3.25), // P top bar (Coral)
      Rect.fromLTWH(16.0, 12.75, 3.25, 3.25), // P right wall (Coral)
      Rect.fromLTWH(12.75, 16.0, 3.25, 3.25), // P bottom loop (Coral)
      Rect.fromLTWH(19.25, 16.0, 3.25, 6.5), // i block (Amber)
    ];

    final partColors = [
      blueColor,
      coralColor,
      coralColor,
      coralColor,
      amberColor,
    ];

    for (var i = 0; i < parts.length; i++) {
      final phase = curve.transform(
        (((progress?.value ?? 1) * 1.6) - (i * 0.12)).clamp(0.0, 1.0),
      );
      canvas.drawRect(
        parts[i].shift(Offset((1 - phase) * (i.isEven ? -6 : 6), 0)),
        Paint()..color = partColors[i].withValues(alpha: 0.15 + 0.85 * phase),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.blueColor != blueColor ||
      old.coralColor != coralColor ||
      old.amberColor != amberColor ||
      old.frameColor != frameColor ||
      old.surfaceColor != surfaceColor ||
      old.progress != progress ||
      old.curve != curve;
}

class BrandWordmark extends StatelessWidget {
  final double size;
  const BrandWordmark({super.key, this.size = 15});
  @override
  Widget build(BuildContext context) => Text(
    'PIFRAME',
    style: TextStyle(
      fontFamily: context.tokens.uiFontFamily,
      fontWeight: FontWeight.w600,
      fontSize: size,
      height: 1,
      letterSpacing: 0.3,
      color: context.tokens.textPrimary,
    ),
  );
}

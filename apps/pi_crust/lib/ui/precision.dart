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

/// An original four-part P glyph. Its component strokes assemble only at
/// application launch, never when selecting sessions or streaming messages.
class CrustMark extends StatelessWidget {
  final double size;
  final Color? color;
  const CrustMark({super.key, this.size = 32, this.color});
  @override
  Widget build(BuildContext context) {
    final progress = context
        .dependOnInheritedWidgetOfExactType<_LaunchScope>()
        ?.progress;
    return Semantics(
      label: 'Pi-Crust',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _MarkPainter(
            color ?? context.tokens.accent,
            context.tokens.enterCurve,
            progress,
          ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  final Curve curve;
  final Animation<double>? progress;
  _MarkPainter(this.color, this.curve, this.progress)
    : super(repaint: progress);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 32, 32));
    const parts = [
      Rect.fromLTWH(0, 0, 8, 32),
      Rect.fromLTWH(8, 0, 24, 8),
      Rect.fromLTWH(24, 8, 8, 12),
      Rect.fromLTWH(8, 12, 16, 8),
    ];
    for (var i = 0; i < parts.length; i++) {
      final phase = curve.transform(
        ((progress?.value ?? 1) * 1.6 - i * 0.14).clamp(0.0, 1.0),
      );
      canvas.drawRect(
        parts[i].shift(Offset((1 - phase) * (i.isEven ? -12 : 12), 0)),
        Paint()..color = color.withValues(alpha: 0.15 + 0.85 * phase),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.color != color || old.progress != progress || old.curve != curve;
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

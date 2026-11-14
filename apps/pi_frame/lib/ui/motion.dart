import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Shared motion timings and curves (DESIGN.md §07 "Motion").
///
/// Reduced motion is decided by `MediaQuery.disableAnimationsOf`. `PiFrameApp`
/// sets that flag when the user enables "Reduce motion" in Appearance, so
/// every widget here follows the setting without knowing about it.
/// Values come from `FrameMotionTokens` in the theme package, which
/// `FrameTokens` also reads, so the two stay in step.
abstract final class FrameMotion {
  /// Zero-duration change.
  static const instant = FrameMotionTokens.instant;

  /// Hover, press and colour changes.
  static const micro = FrameMotionTokens.micro;

  /// Expand/collapse, chips and small state changes.
  static const small = FrameMotionTokens.small;

  /// Panes, side panel and entrances.
  static const panel = FrameMotionTokens.panel;

  /// Exit of small elements.
  static const smallExit = FrameMotionTokens.smallExit;

  /// Exit of panes and side panels.
  static const panelExit = FrameMotionTokens.panelExit;

  /// Dialog entrance.
  static const dialog = FrameMotionTokens.dialog;

  /// Dialog exit.
  static const dialogExit = FrameMotionTokens.dialogExit;

  /// First-run and onboarding transitions.
  static const firstRun = FrameMotionTokens.firstRun;

  /// Delay between items in a staggered entrance.
  static const stagger = FrameMotionTokens.stagger;

  /// Cross-fade used in place of movement under reduced motion (≤150ms).
  static const crossFade = FrameMotionTokens.crossFade;

  /// Ease-out with a fast start: most UI changes.
  static const enterCurve = FrameMotionTokens.enterCurve;

  /// Ease-out with a soft landing: larger surfaces moving across the window.
  static const panelCurve = FrameMotionTokens.panelCurve;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// Fades a newly mounted subtree in and settles it from [offset] pixels below.
///
/// Used where a pane, panel or row appears, so the change has a visible origin
/// instead of snapping. Under reduced motion it cross-fades without moving.
class FrameEnter extends StatefulWidget {
  final Widget child;
  final double offset;
  final Duration duration;

  /// Slide from the right edge instead of from below (side panels, drawers).
  final bool horizontal;

  const FrameEnter({
    super.key,
    required this.child,
    this.offset = 8,
    this.duration = FrameMotion.panel,
    this.horizontal = false,
  });

  @override
  State<FrameEnter> createState() => _FrameEnterState();
}

class _FrameEnterState extends State<FrameEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduced = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = FrameMotion.reduced(context);
    _controller.duration = _reduced ? FrameMotion.crossFade : widget.duration;
    if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: FrameMotion.enterCurve,
    );
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final shift = _reduced ? 0.0 : (1 - curve.value) * widget.offset;
        final offset = widget.horizontal ? Offset(shift, 0) : Offset(0, shift);
        return Opacity(
          opacity: curve.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: offset, child: child),
        );
      },
    );
  }
}

/// Animates the height of [child] open and closed, with a fade.
///
/// Children are built only after the first expansion. Expanding uses
/// [FrameMotion.small]; collapsing uses the shorter [FrameMotion.smallExit].
/// [animate] false applies the state at once, for keyboard-initiated toggles.
class FrameExpandable extends StatefulWidget {
  final bool expanded;
  final Widget child;
  final bool animate;

  const FrameExpandable({
    super.key,
    required this.expanded,
    required this.child,
    this.animate = true,
  });

  @override
  State<FrameExpandable> createState() => _FrameExpandableState();
}

class _FrameExpandableState extends State<FrameExpandable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.expanded ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: FrameMotion.enterCurve,
  );
  bool _everExpanded = false;

  @override
  void initState() {
    super.initState();
    _everExpanded = widget.expanded;
  }

  @override
  void didUpdateWidget(FrameExpandable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;
    if (widget.expanded) _everExpanded = true;
    final target = widget.expanded ? 1.0 : 0.0;
    if (!widget.animate) {
      _controller.value = target;
      return;
    }
    final reduced = FrameMotion.reduced(context);
    _controller.duration = reduced
        ? FrameMotion.crossFade
        : (widget.expanded ? FrameMotion.small : FrameMotion.smallExit);
    _controller.animateTo(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_everExpanded) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        if (t == 0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: Opacity(opacity: t, child: child),
          ),
        );
      },
    );
  }
}

/// Swaps its [child] for a new one with a fade and an optional horizontal
/// slide. The preset behind list ↔ detail swaps (the Git diff in the companion
/// pane) and any later content swap that should read as one change.
///
/// The incoming child fades in and slides from [slide] px to the right; the
/// outgoing child fades out and slides [slide] px to the left. Pass a negative
/// [slide] to reverse the direction, for example when going back. Exits use
/// [exitDuration], which is shorter than [enterDuration]. Under reduced motion
/// the swap is a cross-fade of [FrameMotion.crossFade] with no movement.
///
/// [animate] false swaps at once. Use it for keyboard-driven changes, which
/// the plan keeps instant.
///
/// Every child needs a key: the switcher tells the incoming and the outgoing
/// child apart by it.
class FrameSwitcher extends StatelessWidget {
  final Widget child;
  final double slide;
  final bool animate;
  final Duration enterDuration;
  final Duration exitDuration;
  final Curve curve;

  const FrameSwitcher({
    super.key,
    required this.child,
    this.slide = 8,
    this.animate = true,
    this.enterDuration = FrameMotion.dialog,
    this.exitDuration = FrameMotion.dialogExit,
    this.curve = FrameMotion.enterCurve,
  });

  @override
  Widget build(BuildContext context) {
    assert(child.key != null, 'FrameSwitcher children need a key');
    final reduced = FrameMotion.reduced(context);
    final Duration enter;
    final Duration exit;
    if (!animate) {
      enter = Duration.zero;
      exit = Duration.zero;
    } else if (reduced) {
      enter = FrameMotion.crossFade;
      exit = FrameMotion.crossFade;
    } else {
      enter = enterDuration;
      exit = exitDuration;
    }
    final travel = reduced ? 0.0 : slide;
    final currentKey = child.key;

    return AnimatedSwitcher(
      duration: enter,
      reverseDuration: exit,
      switchInCurve: curve,
      switchOutCurve: curve,
      // The default stack centres children at their own size. Fill the space
      // instead, so a scrolling child keeps its full height.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (widget, animation) {
        if (travel == 0) {
          return FadeTransition(opacity: animation, child: widget);
        }
        // Incoming runs 0 → 1 and settles from +travel. Outgoing runs 1 → 0
        // and ends at -travel, so it leaves the other way. Pixels, not the
        // fractional offsets SlideTransition takes.
        final incoming = widget.key == currentKey;
        final start = incoming ? travel : -travel;
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            child: widget,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                Tween<double>(begin: start, end: 0).evaluate(animation),
                0,
              ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

import 'package:flutter/material.dart';

/// Shared motion timings and curves (DESIGN.md §07 "Motion").
///
/// Reduced motion is decided by `MediaQuery.disableAnimationsOf`. `PiFrameApp`
/// sets that flag when the user enables "Reduce motion" in Appearance, so
/// every widget here follows the setting without knowing about it.
abstract final class FrameMotion {
  /// Hover, press and colour changes.
  static const micro = Duration(milliseconds: 120);

  /// Expand/collapse, chips and small state changes.
  static const small = Duration(milliseconds: 160);

  /// Panes, side panel and entrances.
  static const panel = Duration(milliseconds: 240);

  /// Cross-fade used in place of movement under reduced motion (≤150ms).
  static const crossFade = Duration(milliseconds: 120);

  /// Ease-out with a fast start: most UI changes.
  static const enterCurve = Cubic(0.23, 1, 0.32, 1);

  /// Ease-out with a soft landing: larger surfaces moving across the window.
  static const panelCurve = Cubic(0.32, 0.72, 0, 1);

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
/// Children are built only after the first expansion. Collapsing shrinks the
/// block over [FrameMotion.small] instead of removing it in one frame.
class FrameExpandable extends StatefulWidget {
  final bool expanded;
  final Widget child;

  const FrameExpandable({
    super.key,
    required this.expanded,
    required this.child,
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
    final reduced = FrameMotion.reduced(context);
    _controller.duration = reduced ? FrameMotion.crossFade : FrameMotion.small;
    _controller.animateTo(widget.expanded ? 1 : 0);
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

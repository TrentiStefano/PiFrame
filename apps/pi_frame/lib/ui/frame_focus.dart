import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Draws a keyboard focus ring around [child].
///
/// The ring is a 2 px `focusRing` outline, drawn 2 px outside the child, with
/// the child's corner radius grown to match. It is shown only while the
/// subtree has focus AND focus was reached by keyboard
/// (`FocusHighlightMode.traditional`). Pointer and touch interaction never
/// shows it.
class FrameFocusRing extends StatefulWidget {
  const FrameFocusRing({super.key, required this.child, this.borderRadius});

  final Widget child;

  /// Corner radius of [child]. Defaults to the theme's `radiusSm`.
  final BorderRadius? borderRadius;

  static const double ringWidth = 2;
  static const double ringOffset = 2;

  @override
  State<FrameFocusRing> createState() => _FrameFocusRingState();
}

class _FrameFocusRingState extends State<FrameFocusRing> {
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  bool get _showRing =>
      _hasFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(tokens.radiusSm);
    const outside = FrameFocusRing.ringOffset + FrameFocusRing.ringWidth;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus != _hasFocus) setState(() => _hasFocus = hasFocus);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_showRing)
            Positioned(
              left: -outside,
              top: -outside,
              right: -outside,
              bottom: -outside,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('frame-focus-ring'),
                  decoration: BoxDecoration(
                    borderRadius: _grow(radius, outside),
                    border: Border.all(
                      color: tokens.focusRing,
                      width: FrameFocusRing.ringWidth,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static BorderRadius _grow(BorderRadius radius, double delta) {
    Radius grow(Radius r) => Radius.elliptical(r.x + delta, r.y + delta);
    return BorderRadius.only(
      topLeft: grow(radius.topLeft),
      topRight: grow(radius.topRight),
      bottomLeft: grow(radius.bottomLeft),
      bottomRight: grow(radius.bottomRight),
    );
  }
}

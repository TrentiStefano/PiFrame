import 'package:flutter/widgets.dart';

/// A [ScrollController] that keeps its view pinned to the bottom while the
/// content grows.
///
/// The correction runs during layout ([ScrollPosition.applyContentDimensions]),
/// so the new content and the new offset are painted in the same frame. A
/// post-frame `jumpTo` instead paints one or more frames at a stale offset,
/// which shows as jitter while text streams in.
class BottomAnchoredScrollController extends ScrollController {
  BottomAnchoredScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.shouldAnchorToBottom,
    this.anchorTolerance = 50,
  });

  /// When this returns false the position does not follow new content.
  bool Function()? shouldAnchorToBottom;

  /// Maximum distance from the bottom (in logical pixels) at which the view
  /// still counts as "at the bottom" and follows new content.
  final double anchorTolerance;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BottomAnchoredScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      shouldAnchorToBottom: () => shouldAnchorToBottom?.call() ?? true,
      anchorTolerance: anchorTolerance,
    );
  }
}

class _BottomAnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _BottomAnchoredScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.shouldAnchorToBottom,
    required this.anchorTolerance,
  });

  final bool Function() shouldAnchorToBottom;
  final double anchorTolerance;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final oldMax = hasContentDimensions ? this.maxScrollExtent : null;
    final isDragging = activity is DragScrollActivity;
    final isAtBottom =
        !isDragging &&
        oldMax != null &&
        shouldAnchorToBottom() &&
        (oldMax - pixels).abs() <= anchorTolerance;

    final applied = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );

    if (isAtBottom && maxScrollExtent != oldMax) {
      final delta = maxScrollExtent - oldMax;
      if (delta != 0) {
        final newPixels = (pixels + delta).clamp(
          minScrollExtent,
          maxScrollExtent,
        );
        final correction = newPixels - pixels;
        if (correction.abs() > 0.01) {
          correctBy(correction);
          return false;
        }
      }
    }
    return applied;
  }
}

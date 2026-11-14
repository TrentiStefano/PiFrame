import 'package:flutter/animation.dart';

/// Single source of truth for motion timings and curves.
///
/// `FrameTokens` (theme defaults) and `FrameMotion` (app widgets) both read
/// these constants, so the two cannot drift apart. DESIGN.md §07 "Motion".
abstract final class FrameMotionTokens {
  /// Zero-duration change, for transitions that must not animate.
  static const Duration instant = Duration.zero;

  /// Hover, press and colour changes.
  static const Duration micro = Duration(milliseconds: 120);

  /// Expand/collapse, chips and small state changes.
  static const Duration small = Duration(milliseconds: 160);

  /// Panes, side panel and entrances.
  static const Duration panel = Duration(milliseconds: 240);

  /// Exit of small elements (menus, chips).
  static const Duration smallExit = Duration(milliseconds: 120);

  /// Exit of panes and side panels.
  static const Duration panelExit = Duration(milliseconds: 180);

  /// Dialog entrance.
  static const Duration dialog = Duration(milliseconds: 180);

  /// Dialog exit.
  static const Duration dialogExit = Duration(milliseconds: 120);

  /// First-run and onboarding transitions.
  static const Duration firstRun = Duration(milliseconds: 300);

  /// Delay between items in a staggered list entrance.
  static const Duration stagger = Duration(milliseconds: 100);

  /// Cross-fade used in place of movement under reduced motion (≤150ms).
  static const Duration crossFade = Duration(milliseconds: 120);

  /// Ease-out with a fast start: most UI changes.
  static const Cubic enterCurve = Cubic(0.23, 1, 0.32, 1);

  /// Ease-out with a soft landing: larger surfaces moving across the window.
  static const Cubic panelCurve = Cubic(0.32, 0.72, 0, 1);
}

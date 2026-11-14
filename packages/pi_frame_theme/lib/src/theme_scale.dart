/// Spacing scale in logical pixels (DESIGN.md §07).
///
/// These values do not vary by theme, so they are plain constants.
abstract final class FrameSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
}

/// Control and icon sizes in logical pixels.
abstract final class FrameSize {
  /// Height of a compact list row.
  static const double rowList = 28;

  /// Height of a form row.
  static const double rowForm = 40;

  /// Smallest allowed hit target edge.
  static const double hitMin = 28;

  /// Default icon size.
  static const double icon = 16;

  /// Large icon size.
  static const double iconLg = 20;

  /// Height of a pane header.
  static const double paneHeader = 40;
}

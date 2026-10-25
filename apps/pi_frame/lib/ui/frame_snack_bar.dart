import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Desktop-tailored floating SnackBar that:
/// 1. Appears in the bottom-right of the window (instead of stretching full width).
/// 2. Has minimum and maximum width constraints (min 280px, max 460px).
/// 3. Immediately dismisses when clicked anywhere on the card.
class FrameSnackBar {
  static const double minWidth = 280.0;
  static const double maxWidth = 460.0;
  static const double rightOffset = 16.0;
  static const double bottomOffset = 16.0;

  /// Display a standard frame notification snackbar in the bottom-right.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
    SnackBarAction? action,
    VoidCallback? onTap,
    ScaffoldMessengerState? messenger,
    Key? key,
  }) {
    if (!context.mounted) return null;
    final sm = messenger ?? ScaffoldMessenger.maybeOf(context);
    if (sm == null) return null;

    sm.clearSnackBars();
    return sm.showSnackBar(
      create(
        context,
        content: Text(
          message,
          style: TextStyle(
            color: context.tokens.textPrimary,
            fontSize: 12.5,
            fontFamily: context.tokens.uiFontFamily,
          ),
        ),
        duration: duration,
        backgroundColor: backgroundColor,
        action: action,
        onTap: onTap,
        key: key,
      ),
    );
  }

  /// Create a SnackBar configured for bottom-right alignment with min/max width.
  static SnackBar create(
    BuildContext context, {
    required Widget content,
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    Key? key,
  }) {
    final tokens = context.tokens;
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 800.0;

    final availableWidth = math.max(120.0, screenWidth - (rightOffset * 2));
    final effectiveMax = math.min(maxWidth, availableWidth);
    final effectiveMin = math.min(minWidth, effectiveMax);

    int textLength = 40;
    if (content is Text && content.data != null) {
      textLength = content.data!.length;
    }

    final estimatedWidth = (textLength * 8.5 + 88.0).clamp(effectiveMin, effectiveMax);
    final targetWidth = estimatedWidth.clamp(effectiveMin, effectiveMax);
    final leftMargin = math.max(rightOffset, screenWidth - targetWidth - rightOffset);

    return SnackBar(
      key: key,
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      backgroundColor: backgroundColor ?? tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.borderStrong),
      ),
      padding: EdgeInsets.zero,
      margin: margin ??
          EdgeInsets.only(
            left: leftMargin,
            right: rightOffset,
            bottom: bottomOffset,
          ),
      duration: duration,
      content: Builder(
        builder: (innerContext) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                ScaffoldMessenger.maybeOf(innerContext)?.hideCurrentSnackBar();
                onTap?.call();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(child: content),
                    if (action != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.maybeOf(innerContext)?.hideCurrentSnackBar();
                          action.onPressed();
                        },
                        child: Text(action.label),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Icon(
                      Icons.close,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

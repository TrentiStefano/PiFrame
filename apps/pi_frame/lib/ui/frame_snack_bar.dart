import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'motion.dart';

/// Desktop-tailored floating SnackBar that:
/// 1. Appears in the bottom-right of the window (instead of stretching full width).
/// 2. Has minimum and maximum width constraints (min 280px, max 460px).
/// 3. Dismisses when its card is activated (click, Enter or Space when focused).
/// 4. Success messages auto-dismiss after [successDuration] (4 s).
/// 5. Errors (`isError: true`) stay until dismissed with their ✕ control and
///    are announced to screen readers with [SemanticsService].
///
/// Enter: content rises [_enterRise] px while it fades in over
/// `FrameMotion.dialog` (180 ms). Under reduced motion it cross-fades over
/// `FrameMotion.crossFade` with no rise.
class FrameSnackBar {
  static const double minWidth = 280.0;
  static const double maxWidth = 460.0;
  static const double rightOffset = 16.0;
  static const double bottomOffset = 16.0;

  /// How long a success message stays before it dismisses itself.
  static const Duration successDuration = Duration(seconds: 4);

  static const double _enterRise = 8.0;

  /// Display a standard frame notification snackbar in the bottom-right.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context, {
    required String message,
    Duration? duration,
    Color? backgroundColor,
    SnackBarAction? action,
    VoidCallback? onTap,
    ScaffoldMessengerState? messenger,
    Key? key,
    bool isError = false,
  }) {
    if (!context.mounted) return null;
    final sm = messenger ?? ScaffoldMessenger.maybeOf(context);
    if (sm == null) return null;

    sm.clearSnackBars();
    if (isError) _announce(context, message);
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
        isError: isError,
      ),
    );
  }

  /// Create a SnackBar configured for bottom-right alignment with min/max width.
  static SnackBar create(
    BuildContext context, {
    required Widget content,
    Duration? duration,
    Color? backgroundColor,
    SnackBarAction? action,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    Key? key,
    bool isError = false,
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
    final reduced = FrameMotion.reduced(context);

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
      duration: duration ?? successDuration,
      // Errors stay until the user dismisses them with the ✕ control.
      persist: isError,
      showCloseIcon: isError,
      closeIconColor: tokens.textMuted,
      content: _SnackBarEnter(
        reduced: reduced,
        child: Builder(
          builder: (innerContext) {
            void dismiss() =>
                ScaffoldMessenger.maybeOf(innerContext)?.hideCurrentSnackBar();
            // The SnackBar supplies the Material ancestor for the InkWell.
            return InkWell(
              key: const ValueKey('frame-snack-bar-card'),
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              onTap: () {
                dismiss();
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
                          dismiss();
                          action.onPressed();
                        },
                        child: Text(action.label),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static void _announce(BuildContext context, String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }
}

/// Enter motion for a SnackBar card: fade in and rise [FrameSnackBar._enterRise]
/// px over 180 ms, or cross-fade in place under reduced motion.
class _SnackBarEnter extends StatelessWidget {
  final bool reduced;
  final Widget child;

  const _SnackBarEnter({required this.reduced, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: reduced ? FrameMotion.crossFade : FrameMotion.dialog,
      curve: FrameMotion.enterCurve,
      child: child,
      builder: (context, t, child) {
        final rise = reduced ? 0.0 : (1 - t) * FrameSnackBar._enterRise;
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, rise), child: child),
        );
      },
    );
  }
}

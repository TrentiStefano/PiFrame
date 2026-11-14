import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'motion.dart';

/// Role of a dialog action. Drives the button style:
/// [cancel] is a text button, [primary] a filled button in the accent colour
/// and [destructive] a filled button with the `danger` fill.
enum FrameDialogActionRole { cancel, primary, destructive }

/// One action in a [FrameDialog]. Tapping it runs [onPressed] and closes the
/// dialog with [value] as the result of [showFrameDialog].
class FrameDialogAction<T> {
  final String label;
  final FrameDialogActionRole role;
  final T? value;
  final VoidCallback? onPressed;

  /// Defaults to `ValueKey('frame-dialog-<role>')` when omitted.
  final ValueKey<String>? key;

  const FrameDialogAction({
    required this.label,
    required this.role,
    this.value,
    this.onPressed,
    this.key,
  });
}

/// Confirmation or form dialog: a [title] in the heading role, a scrollable
/// [body] and right-aligned [actions].
///
/// When any action is [FrameDialogActionRole.destructive], the cancel action
/// gets the initial focus, so Enter does not run the destructive action.
/// Height fits the content up to 80 % of the window, then the body scrolls.
///
/// Use with [showFrameDialog].
class FrameDialog<T> extends StatelessWidget {
  /// Largest share of the window height the dialog may use.
  static const double maxHeightFraction = 0.8;

  static const double _maxWidth = 480;

  final String title;
  final Widget body;
  final List<FrameDialogAction<T>> actions;

  const FrameDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final hasDestructive = actions.any(
      (a) => a.role == FrameDialogActionRole.destructive,
    );
    final maxHeight =
        MediaQuery.sizeOf(context).height * maxHeightFraction;

    return Dialog(
      insetPadding: const EdgeInsets.all(FrameSpace.x6),
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: maxHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(FrameSpace.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.heading.copyWith(color: tokens.textPrimary),
                ),
              ),
              const SizedBox(height: FrameSpace.x3),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: DefaultTextStyle.merge(
                    style: text.bodyLarge.copyWith(
                      color: tokens.textSecondary,
                    ),
                    child: body,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: FrameSpace.x6),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: FrameSpace.x2,
                  runSpacing: FrameSpace.x2,
                  children: [
                    for (final action in actions)
                      _buildAction(
                        context,
                        action,
                        autofocus: hasDestructive &&
                            action.role == FrameDialogActionRole.cancel,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    FrameDialogAction<T> action, {
    required bool autofocus,
  }) {
    final tokens = context.tokens;
    final key = action.key ??
        ValueKey('frame-dialog-${action.role.name}');

    void press() {
      action.onPressed?.call();
      Navigator.of(context).pop(action.value);
    }

    switch (action.role) {
      case FrameDialogActionRole.cancel:
        return TextButton(
          key: key,
          autofocus: autofocus,
          onPressed: press,
          child: Text(action.label),
        );
      case FrameDialogActionRole.primary:
        return FilledButton(
          key: key,
          onPressed: press,
          child: Text(action.label),
        );
      case FrameDialogActionRole.destructive:
        return FilledButton(
          key: key,
          style: FilledButton.styleFrom(
            backgroundColor: tokens.danger,
            foregroundColor: tokens.surface,
          ),
          onPressed: press,
          child: Text(action.label),
        );
    }
  }
}

/// Shows [dialog] as a modal and completes with the value of the action that
/// closed it, or null when dismissed.
///
/// Motion: fade plus a 0.97 → 1 scale on the `dialog` / `dialogExit` tokens
/// with the enter curve. Under reduced motion it cross-fades over
/// `FrameMotion.crossFade` with no scale. [instant] removes the transition, for
/// overlays opened from the keyboard.
Future<T?> showFrameDialog<T>({
  required BuildContext context,
  required FrameDialog<T> dialog,
  bool instant = false,
}) {
  final reduced = FrameMotion.reduced(context);
  final tokens = context.tokens;
  final enterDuration = instant
      ? Duration.zero
      : (reduced ? FrameMotion.crossFade : FrameMotion.dialog);
  final exitDuration = instant
      ? Duration.zero
      : (reduced ? FrameMotion.crossFade : FrameMotion.dialogExit);

  return Navigator.of(context, rootNavigator: true).push<T>(
    _FrameDialogRoute<T>(
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: tokens.overlay,
      transitionDuration: enterDuration,
      reverseDuration: exitDuration,
      pageBuilder: (routeContext, animation, secondaryAnimation) => dialog,
      transitionBuilder: (routeContext, animation, secondaryAnimation, child) {
        if (instant) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: FrameMotion.enterCurve,
        );
        if (reduced) {
          return FadeTransition(opacity: curved, child: child);
        }
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// The route behind [showFrameDialog]. Same as the route `showGeneralDialog`
/// builds, plus a separate exit duration, which `showGeneralDialog` lacks.
class _FrameDialogRoute<T> extends RawDialogRoute<T> {
  _FrameDialogRoute({
    required super.pageBuilder,
    required super.transitionBuilder,
    required super.barrierColor,
    required super.barrierLabel,
    required super.transitionDuration,
    required this.reverseDuration,
  });

  final Duration reverseDuration;

  @override
  Duration get reverseTransitionDuration => reverseDuration;
}

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

  /// When false the button is shown disabled and does nothing when tapped.
  final bool enabled;

  /// Defaults to `ValueKey('frame-dialog-<role>')` when omitted.
  final ValueKey<String>? key;

  const FrameDialogAction({
    required this.label,
    required this.role,
    this.value,
    this.onPressed,
    this.enabled = true,
    this.key,
  });
}

/// Confirmation or form dialog: a [title] in the heading role, a scrollable
/// [body] and right-aligned [actions].
///
/// [headerActions] are small icon buttons (for example `FrameIconAction`)
/// shown at the end of the title row, such as refresh or copy.
///
/// When any action is [FrameDialogActionRole.destructive], the cancel action
/// gets the initial focus, so Enter does not run the destructive action.
/// Height fits the content up to 80 % of the window, then the body scrolls.
///
/// Use with [showFrameDialog].
class FrameDialog<T> extends StatelessWidget {
  /// Largest share of the window height the dialog may use.
  static const double maxHeightFraction = 0.8;

  /// Default width cap. Wide content, such as a diff, passes its own [maxWidth].
  static const double defaultMaxWidth = 480;

  final String title;
  final Widget body;
  final List<FrameDialogAction<T>> actions;
  final double maxWidth;
  final List<Widget> headerActions;

  const FrameDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.maxWidth = defaultMaxWidth,
    this.headerActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final hasDestructive = actions.any(
      (a) => a.role == FrameDialogActionRole.destructive,
    );
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFraction;

    return Dialog(
      insetPadding: const EdgeInsets.all(FrameSpace.x6),
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(FrameSpace.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: text.heading.copyWith(color: tokens.textPrimary),
                      ),
                    ),
                  ),
                  for (final action in headerActions) ...[
                    const SizedBox(width: FrameSpace.x2),
                    action,
                  ],
                ],
              ),
              const SizedBox(height: FrameSpace.x3),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: DefaultTextStyle.merge(
                    style: text.bodyLarge.copyWith(color: tokens.textSecondary),
                    child: body,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: FrameSpace.x6),
                // Align expands to the full width so the Wrap's end alignment
                // applies even when there is a single action.
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
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
    final key = action.key ?? ValueKey('frame-dialog-${action.role.name}');

    void press() {
      action.onPressed?.call();
      Navigator.of(context).pop(action.value);
    }

    final onPressed = action.enabled ? press : null;

    switch (action.role) {
      case FrameDialogActionRole.cancel:
        return TextButton(
          key: key,
          autofocus: autofocus,
          onPressed: onPressed,
          child: Text(action.label),
        );
      case FrameDialogActionRole.primary:
        return FilledButton(
          key: key,
          onPressed: onPressed,
          child: Text(action.label),
        );
      case FrameDialogActionRole.destructive:
        return FilledButton(
          key: key,
          style: FilledButton.styleFrom(
            backgroundColor: tokens.danger,
            foregroundColor: tokens.surface,
          ),
          onPressed: onPressed,
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
}) => showFrameDialogBuilder<T>(
  context: context,
  builder: (_) => dialog,
  instant: instant,
);

/// Like [showFrameDialog], for a dialog whose content is stateful: [builder]
/// builds the [FrameDialog] inside the route, so its own `setState` can change
/// the body and the actions (for example to disable the confirm button).
Future<T?> showFrameDialogBuilder<T>({
  required BuildContext context,
  required WidgetBuilder builder,
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
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          builder(routeContext),
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
